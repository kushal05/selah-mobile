#!/usr/bin/env python3
"""WCAG contrast audit for both themes.

Parses the colour tokens straight out of lib/core/theme/app_theme.dart and
checks every pairing the app actually renders, in light and dark. Fails with a
non-zero exit if any pairing drops below its WCAG 2.1 minimum:

  4.5:1  normal text
  3.0:1  graphical objects, UI component boundaries, large text

It then scans lib/ for foreground colour literals that never reach the token
system at all — the gap that let 169 failing colours sit behind a passing
audit.

This exists because contrast regressions are invisible in review and in
`flutter analyze` — a one-line palette tweak can silently push a label under
the threshold on one theme while looking fine on the other.

Usage:  python3 tool/contrast_audit.py [--verbose]
"""
import re
import sys
import pathlib

THEME = pathlib.Path(__file__).parent.parent / 'lib/core/theme/app_theme.dart'


def load_tokens():
    src = THEME.read_text(encoding='utf-8')
    tokens = {}
    for m in re.finditer(
            r'static const Color (\w+) = Color\(0x(?:FF|1A)([0-9A-Fa-f]{6})\);', src):
        tokens[m.group(1)] = '#' + m.group(2).upper()
    for _ in range(3):  # resolve aliases like `hintColor = textMuted`
        for m in re.finditer(r'static const Color (\w+) = (\w+);', src):
            if m.group(2) in tokens:
                tokens[m.group(1)] = tokens[m.group(2)]
    return tokens


def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(h):
    h = h.lstrip('#')
    return (0.2126 * _lin(int(h[0:2], 16))
            + 0.7152 * _lin(int(h[2:4], 16))
            + 0.0722 * _lin(int(h[4:6], 16)))


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return round((hi + 0.05) / (lo + 0.05), 2)


def lerp(a, b, t):
    a, b = a.lstrip('#'), b.lstrip('#')
    return '#%02X%02X%02X' % tuple(
        round(int(a[i:i + 2], 16) * (1 - t) + int(b[i:i + 2], 16) * t)
        for i in (0, 2, 4))


def over(fg, alpha, bg):
    """fg composited onto bg at alpha."""
    return lerp(bg, fg, alpha)


ACCENTS = ['brandBlue', 'brandPurple', 'emerald', 'rosePink', 'orange', 'teal']
SEMANTICS = ['success', 'error', 'warning', 'info', 'statusOpen',
             'statusInProgress', 'statusResolved', 'mutedGrey']
HIGHLIGHTS = {'yellow': '#FFF9C4', 'green': '#C8E6C9', 'blue': '#BBDEFB',
              'pink': '#F8BBD0', 'orange': '#FFE0B2', 'purple': '#E1BEE7'}


def build_cases(T):
    cases = []

    def add(theme, area, what, fg, bg, need):
        cases.append((theme, area, what, fg, bg, ratio(fg, bg), need))

    for theme in ('light', 'dark'):
        dark = theme == 'dark'
        surface = T['darkSurface'] if dark else '#FFFFFF'
        page = T['darkScaffold'] if dark else T['scaffoldGray']
        raised = T['darkSurfaceRaised'] if dark else '#FFFFFF'
        text = T['darkTextPrimary'] if dark else T['textDark']
        muted = T['darkTextMuted'] if dark else T['textMuted']

        add(theme, 'Body', 'primary on surface', text, surface, 4.5)
        add(theme, 'Body', 'primary on page', text, page, 4.5)
        add(theme, 'Body', 'muted on surface', muted, surface, 4.5)
        add(theme, 'Body', 'muted on page', muted, page, 4.5)

        add(theme, 'Input', 'hint', muted, raised, 4.5)
        add(theme, 'Input', 'border at rest',
            T['darkInputBorder'] if dark else T['inputBorderColor'], raised, 3.0)
        add(theme, 'Input', 'focus ring',
            T['brandBlueOnDark'] if dark else T['brandBlue'], raised, 3.0)
        add(theme, 'Input', 'error border',
            T['errorOnDark'] if dark else T['errorOnLight'], raised, 3.0)

        add(theme, 'Nav', 'unselected label', muted, surface, 4.5)
        for a in ACCENTS[:4]:  # the four primary tabs
            add(theme, 'Nav', f'selected {a}',
                T[a + ('OnDark' if dark else 'OnLight')], surface, 4.5)

        for a in ACCENTS:
            glyph = T[a + ('OnDark' if dark else 'OnLight')]
            # cardGradient runs from an 0.80 mix to an 0.68 mix, so the most
            # saturated stop — not the average — is the background the text
            # has to survive. The audit used to check only the 0.80 stop and
            # so graded the cards on the easier half of their own gradient.
            card = lerp(T[a], surface if dark else '#FFFFFF', 0.68)
            badge = over(T[a], 0.10, surface)
            add(theme, 'Card tint', f'{a} primary text',
                text if dark else T['onTintPrimary'], card, 4.5)
            # Tinted cards use their own muted neutral in dark mode: the
            # page-level darkTextMuted falls to 3.46:1 on the teal card.
            add(theme, 'Card tint', f'{a} secondary text',
                T['onTintMutedOnDark'] if dark else T['onTintSecondary'],
                card, 4.5)
            add(theme, 'Card tint', f'{a} glyph', glyph, card, 3.0)
            # The glyph actually sits on an accent badge over the card, which
            # lifts its background — checking it against the bare card missed
            # brandBlue at 2.92:1 on the overview cards.
            add(theme, 'Card tint', f'{a} glyph on badge', glyph,
                over(T[a], 0.12, card), 3.0)

            # Hued text on tinted cards (overview counts/titles, quick action
            # labels). Same background, but these must read as body text.
            ink_key = {'brandBlue': 'inkBlue', 'brandPurple': 'inkPurple',
                       'emerald': 'inkEmerald', 'rosePink': 'inkRose',
                       'orange': 'inkOrange', 'teal': 'inkTeal'}[a]
            ink = T[ink_key + ('OnDark' if dark else '')]
            ink_muted = T[ink_key + ('OnDarkMuted' if dark else 'Muted')]
            # The big count uses the card's icon colour so the two read as
            # one object. At 32px/w800 (30px/w700 on the prayers dashboard)
            # it is WCAG large text, so the bar is 3:1, not 4.5:1.
            add(theme, 'Card number', f'{a} count on card', glyph, card, 3.0)
            add(theme, 'Card ink', f'{a} tinted primary', ink, card, 4.5)
            add(theme, 'Card ink', f'{a} tinted muted', ink_muted, card, 4.5)
            # Quick action buttons use a flatter 0.84 tint.
            qa = lerp(T[a], surface if dark else '#FFFFFF',
                      0.80 if dark else 0.84)
            add(theme, 'Card ink', f'{a} quick action label', ink, qa, 4.5)
            add(theme, 'Badge', f'{a} label on own tint', glyph, badge, 4.5)
            add(theme, 'Badge', f'{a} icon on own tint', glyph, badge, 3.0)
            add(theme, 'Button', f'{a} filled label',
                T['darkScaffold'] if dark else '#FFFFFF', glyph, 4.5)
            add(theme, 'Accent text', f'{a} on surface', glyph, surface, 4.5)

        # Chevrons and dividers read colorScheme.outline via
        # context.decorativeInk, so the outline role is what to check.
        # colorScheme.error is read directly at 27 sites. In light it is
        # Flutter's own default (#B00020) rather than one of our tokens, so
        # it is pinned here explicitly — a default nobody chose is still a
        # colour users read.
        add(theme, 'Scheme', 'error text',
            '#FFB4AB' if dark else '#B00020', surface, 4.5)
        add(theme, 'Scheme', 'on-error on error',
            '#000000' if dark else '#FFFFFF',
            '#FFB4AB' if dark else '#B00020', 4.5)

        # Two kinds of solid accent block, with different bars.
        #
        # A FAB keeps the true accent and picks its glyph — an icon needs 3:1,
        # and darkening the fill so white works turned orange into brown.
        for a in ACCENTS:
            white_r = ratio('#FFFFFF', T[a])
            ink_r = ratio(T['textDark'], T[a])
            glyph = '#FFFFFF' if white_r >= ink_r else T['textDark']
            add(theme, 'Accent fill', f'{a} FAB glyph', glyph, T[a], 3.0)

        # A fill carrying a *label* needs 4.5, which the raw accent cannot
        # give, so those use the darkened surface.
        for a in ACCENTS:
            add(theme, 'Accent fill', f'{a} label on filled surface',
                '#FFFFFF', T[a + 'Surface'], 4.5)

        # Chip labels, both states, in both themes. The selected label was
        # left to Material's default and resolved against a container role
        # this app never set.
        chip_bg = T['darkSurfaceRaised'] if dark else T['containerHigh']
        # The selected tint paints over the chip's own ground, not the page.
        chip_sel = over(
            T['brandBlueOnDark'] if dark else T['brandBlue'],
            0.15 if dark else 0.12,
            chip_bg,
        )
        add(theme, 'Chip', 'label', text if dark else T['textDark'],
            chip_bg, 4.5)
        add(theme, 'Chip', 'selected label',
            T['brandBlueOnDark'] if dark else T['inkBlue'], chip_sel, 4.5)
        # A tab that tints its own chips (People uses teal) still has to
        # clear the bar on its own ground.
        for a in ACCENTS:
            tinted = over(T[a], 0.12, chip_bg)
            ink_key = {'brandBlue': 'inkBlue', 'brandPurple': 'inkPurple',
                       'emerald': 'inkEmerald', 'rosePink': 'inkRose',
                       'orange': 'inkOrange', 'teal': 'inkTeal'}[a]
            add(theme, 'Chip', f'{a}-tinted selected label',
                T[ink_key + ('OnDark' if dark else '')], tinted, 4.5)


        add(theme, 'Chip', 'border',
            T['darkBorder'] if dark else T['hairlineLight'], surface, 1.2)

        add(theme, 'Chevron', 'chevron',
            T['darkCardBorder'] if dark else T['outlineLight'], surface, 3.0)
        add(theme, 'Chevron', 'chevron on page',
            T['darkCardBorder'] if dark else T['outlineLight'],
            T['darkScaffold'] if dark else T['scaffoldGray'], 3.0)

        # Container and outline roles. ~100 call sites read these through
        # colorScheme, so they need checking like any other pairing — text has
        # to stay legible on the fills, and an edge has to stay visible.
        c_high = T['darkContainerHigh'] if dark else T['containerHigh']
        c_highest = (T['darkContainerHighest'] if dark
                     else T['containerHighest'])
        for label, fill in (('container high', c_high),
                            ('container highest', c_highest)):
            add(theme, 'Container', f'{label} body text', text, fill, 4.5)
            add(theme, 'Container', f'{label} muted text', muted, fill, 4.5)
        add(theme, 'Container', 'component outline',
            T['darkCardBorder'] if dark else T['outlineLight'], surface, 3.0)

        # Swipe action tiles sit on the intro banner's tint: the adjusted
        # accent at 8% over the page, behind a 25% border.
        for name, a in (('trash', 'error'), ('move', 'brandPurple'),
                        ('restore', 'emerald')):
            glyph = T[a + ('OnDark' if dark else 'OnLight')]
            ink_key = {'error': 'inkError', 'brandPurple': 'inkPurple',
                       'emerald': 'inkEmerald'}[a]
            tile = over(glyph, 0.08, surface)
            add(theme, 'Swipe', f'{name} label',
                T[ink_key + ('OnDark' if dark else '')], tile, 4.5)
            add(theme, 'Swipe', f'{name} icon', glyph, tile, 3.0)
            add(theme, 'Swipe', f'{name} border',
                over(glyph, 0.25, surface), surface, 1.2)

        # Snackbars keep the same ground in both themes, so their contrast is
        # theme-independent — but it was 3.68:1 white-on-red before the
        # errorSurface token, and the Undo label was 3.98:1.
        add(theme, 'Snackbar', 'content on ground', '#FFFFFF',
            T['snackBackground'], 4.5)
        add(theme, 'Snackbar', 'action label on ground', T['snackAction'],
            T['snackBackground'], 4.5)
        add(theme, 'Snackbar', 'content on error ground', '#FFFFFF',
            T['errorSurface'], 4.5)

        # Highlights are light pastels in BOTH themes, so their foreground is
        # near-black regardless — see AppTheme.onHighlight.
        for name, bg in HIGHLIGHTS.items():
            add(theme, 'Highlight', f'verse on {name}', T['onHighlight'], bg, 4.5)

        for n in SEMANTICS:
            c = (T['errorOnDark'] if n == 'error' else T[n]) if dark \
                else T[n + 'OnLight']
            add(theme, 'Semantic', f'{n} as text', c, surface, 4.5)
            add(theme, 'Semantic', f'{n} on own tint', c, over(T[n], 0.07, surface), 4.5)

        if dark:
            add(theme, 'Card', 'edge on surface', T['darkCardBorder'], surface, 3.0)
            add(theme, 'Card', 'edge on page', T['darkCardBorder'], page, 3.0)

    return cases


# ── Foreground colour literals in lib/ ──────────────────────────────────────
# The pairing checks above read colours out of app_theme.dart, so they are
# blind to a widget that writes `Colors.grey.shade400` directly. 169 of those
# existed when this scan was added, none of them meeting 4.5:1 — the token
# audit passed the whole time. A colour the design system never sees is a
# colour nobody has checked.

LIB = pathlib.Path(__file__).parent.parent / 'lib'

# Material's own palette, as actually rendered.
MATERIAL = {
    'grey.shade200': '#EEEEEE', 'grey.shade300': '#E0E0E0',
    'grey.shade400': '#BDBDBD', 'grey.shade500': '#9E9E9E',
    'grey.shade600': '#757575', 'grey.shade700': '#616161',
    'grey.shade800': '#424242', 'grey': '#9E9E9E',
    'red': '#F44336', 'red.shade300': '#E57373', 'red.shade400': '#EF5350',
    'red.shade700': '#D32F2F',
    'green': '#4CAF50', 'green.shade400': '#66BB6A', 'green.shade700': '#388E3C',
    'orange': '#FF9800', 'orange.shade400': '#FFA726', 'orange.shade700': '#F57C00',
    'blue': '#2196F3', 'blue.shade400': '#42A5F5', 'blue.shade700': '#1976D2',
    'amber': '#FFC107', 'yellow': '#FFEB3B', 'teal': '#009688',
    'purple': '#9C27B0', 'pink': '#E91E63', 'brown': '#795548',
    'black54': '#8A8A8A', 'black45': '#9D9D9D', 'black38': '#ABABAB',
    'black26': '#BDBDBD', 'black12': '#DFDFDF',
}

# A foreground literal is only a finding when it is drawn as text or a glyph.
FOREGROUND_CONTEXT = ('TextStyle', 'Icon(', 'hintStyle', 'labelStyle',
                      'helperStyle', 'errorStyle', 'iconColor',
                      # `textTheme.titleMedium?.copyWith(color: …)` never
                      # contains the word TextStyle, so a whole idiom of
                      # foreground colours was invisible to this check.
                      'foregroundColor', 'copyWith(', 'style:', 'Text(')

# `black87` and friends must be captured whole: matching only the letters
# left `87` behind and the token read as plain `black`, which the allow-list
# waves through — so a theme-blind foreground passed as a painted-ground one.
# Any `Colors.<name>`, wherever it appears — not just immediately after a
# `color:`. The previous pattern required Colors. to follow `color:` directly,
# so every conditional escaped it:
#
#     color: isChecked ? Colors.grey : null     <- never matched
#     foregroundColor: Colors.red               <- never matched
#
# That left 89 theme-blind literals in 37 files while the gate reported "no
# failing colour literals in lib/". A rule true by construction cannot be
# evaded by a ternary, a ??, or a property name nobody thought to list.
# `(?<![A-Za-z0-9_])` keeps PdfColors.grey600 from reading as Colors.grey600.
LITERAL_RE = re.compile(
    r'(?<![A-Za-z0-9_])Colors\.([A-Za-z]+\d*(?:\.shade\d+)?)\b')

# White, black and their opacity variants are legitimate foregrounds on a
# painted ground (a gradient hero, a filled button) and are checked as
# pairings above. Every other Colors.* value used as a foreground is a raw
# Material colour: fixed to one theme and measured by nobody.
# White variants sit on painted grounds (gradients, filled buttons) and are
# checked as pairings. Black variants only ever work on a light surface, so
# they are *not* exempt — `Colors.black87` as body text is invisible in dark.
ALLOWED_LITERALS = {
    'white', 'white70', 'white60', 'white54', 'white38', 'white30', 'white24',
    'white12', 'white10', 'black', 'transparent',
}


# Palette entries that only make sense on a light ground. Used as a
# foreground anywhere, they are invisible or near-invisible in dark mode.
# The first migration matched `color: AppTheme.x` and so missed every one
# reached through a ternary — 46 of them, including the whole text-size
# sheet. Matching the token itself closes that.
LIGHT_ONLY_TOKENS = (
    'textDark', 'textMuted', 'hintColor', 'chevronColor', 'unselectedColor',
    'gray50', 'gray100', 'gray200', 'gray300', 'gray400', 'gray500',
    'gray600', 'gray700', 'onTintPrimary', 'onTintSecondary', 'scaffoldGray',
    'borderColor', 'dividerColor',
    # The Bible reader's accent pair. Applied unconditionally in the chapter
    # screen's theme override, it rendered a light green translation pill on a
    # near-black bar. Use bibleSurfaceFor/bibleInkFor instead.
    'bibleBackground', 'bibleForeground',
)
LIGHT_TOKEN_RE = re.compile(
    r'\bAppTheme\.(' + '|'.join(LIGHT_ONLY_TOKENS) + r')\b')


def scan_light_tokens():
    """Light-only tokens used where a colour is being chosen.

    Reported separately from the Colors.* literals because the fix differs:
    these are already design tokens, they are simply the wrong half of a pair.
    """
    findings = []
    for path in sorted(LIB.rglob('*.dart')):
        if 'core/theme' in path.parts or path.name == 'app_theme.dart':
            continue
        lines = path.read_text(encoding='utf-8').split('\n')
        for i, line in enumerate(lines):
            m = LIGHT_TOKEN_RE.search(line)
            if not m:
                continue
            context = '\n'.join(lines[max(0, i - 4):i + 2])
            if not any(k in context for k in FOREGROUND_CONTEXT):
                continue
            findings.append((str(path.relative_to(LIB.parent)), i + 1,
                             m.group(1)))
    return findings


# Tokens that name a *surface*: something a shape is painted with, never
# something text or a glyph is drawn in. context.subtleFill is
# surfaceContainerHighest — a chip ground — and as text it measured 1.22:1 on
# the dark card and 1.10:1 on the light page. It was the colour of the note
# detail screen's date and preacher line, which is to say those were not
# visible in either theme.
#
# The pairing audit above could not see this: it checks the foreground tokens
# against the grounds they sit on, and a fill token is not in that list. So
# this rule works the other way round — it finds fills in a position where a
# foreground belongs, whatever their contrast happens to be.
FILL_TOKENS = ('subtleFill', 'cardSurface', 'raisedSurface', 'pageGround',
               'hairline')
FILL_RE = re.compile(r'context\.(' + '|'.join(FILL_TOKENS) + r')\b')

# Constructors whose colour argument paints text or a glyph.
FOREGROUND_CTORS = {
    'TextStyle', 'Icon', 'IconThemeData', 'ImageIcon',
    'CircularProgressIndicator', 'LinearProgressIndicator',
}
# Named arguments that settle it either way, whatever the constructor is.
FOREGROUND_ARGS = {
    'foregroundColor', 'iconColor', 'textColor', 'labelColor',
    'unselectedLabelColor', 'cursorColor',
}
BACKGROUND_ARGS = {
    'backgroundColor', 'fillColor', 'surfaceTintColor', 'barrierColor',
    'shadowColor', 'selectedTileColor', 'indicatorColor', 'splashColor',
    'highlightColor', 'overlayColor', 'trackColor', 'thumbColor',
}


def _enclosing(src, pos):
    """The nearest unclosed `Name(` before pos, and the named argument we are
    inside. Counting brackets rather than reading the few lines above is what
    keeps a nested TextStyle from being credited to the Container around it."""
    depth, i, arg = 0, pos - 1, None
    while i >= 0:
        c = src[i]
        if c == ')':
            depth += 1
        elif c == '(':
            if depth == 0:
                j = i - 1
                while j >= 0 and (src[j].isalnum() or src[j] == '_'):
                    j -= 1
                return src[j + 1:i], arg
            depth -= 1
        elif c == ':' and depth == 0 and arg is None:
            j = i - 1
            while j >= 0 and (src[j].isalnum() or src[j] == '_'):
                j -= 1
            arg = src[j + 1:i]
        i -= 1
    return None, arg


def scan_fill_as_foreground():
    """Surface tokens used to colour text or an icon."""
    findings = []
    for path in sorted(LIB.rglob('*.dart')):
        if path.name == 'theme_colors.dart':
            continue
        src = path.read_text(encoding='utf-8')
        for m in FILL_RE.finditer(src):
            ctor, arg = _enclosing(src, m.start())
            if arg in BACKGROUND_ARGS:
                continue
            if arg not in FOREGROUND_ARGS and ctor not in FOREGROUND_CTORS:
                continue
            line = src[:m.start()].count('\n') + 1
            findings.append((str(path.relative_to(LIB.parent)), line,
                             m.group(1), ctor or '?'))
    return findings


def scan_literals():
    """Foreground colour literals below 4.5:1 on either theme's ground.

    Checked against white AND the dark scaffold, because a raw Colors.* value
    is the same colour in both themes by construction — it cannot adapt. A
    light-only check passed 24 greys that fail in dark mode: grey.shade700 at
    3.02:1 and grey.shade800 at 1.86:1. Failing in one theme is failing.
    """
    T = load_tokens()
    dark_ground = T['darkScaffold']
    findings = []
    for path in sorted(LIB.rglob('*.dart')):
        lines = path.read_text(encoding='utf-8').split('\n')
        for i, line in enumerate(lines):
            for m in LITERAL_RE.finditer(line):
              name = m.group(1)
              if name.split('.')[0] in ALLOWED_LITERALS:
                continue
              context = '\n'.join(lines[max(0, i - 4):i + 2])
              if not any(k in context for k in FOREGROUND_CONTEXT):
                continue
              # Flag by construction, not by lookup. The previous version
              # only knew a handful of shades, so `Colors.amber.shade800` —
              # 2.15:1 on white, in the offline banner — passed because it
              # was absent from the table. A colour the design system never
              # sees is unchecked whether or not this file knows its hex.
              hexv = MATERIAL.get(name)
              if hexv:
                light = ratio(hexv, '#FFFFFF')
                darkr = ratio(hexv, dark_ground)
                r = min(light, darkr)
              else:
                r = 0.0
              if hexv is None or r < 4.5:
                rel = path.relative_to(LIB.parent)
                findings.append((str(rel), i + 1, name, hexv or '(unknown)', r))
    return findings


def main():
    verbose = '--verbose' in sys.argv
    T = load_tokens()
    cases = build_cases(T)
    fails = [c for c in cases if c[5] < c[6]]

    for theme in ('light', 'dark'):
        sub = [c for c in cases if c[0] == theme]
        bad = [c for c in sub if c[5] < c[6]]
        status = 'all pass' if not bad else f'{len(bad)} FAIL'
        print(f'  {theme:5} {len(sub) - len(bad)}/{len(sub)}  {status}')
        if verbose:
            for area in dict.fromkeys(c[1] for c in sub):
                a = [c for c in sub if c[1] == area]
                print(f'        {area:12} worst {min(c[5] for c in a):6.2f}')

    if fails:
        print('\ncontrast_audit: FAILURES')
        for theme, area, what, fg, bg, r, need in fails:
            print(f'  [{theme}] {area} — {what}: {fg} on {bg} = {r}:1, need {need}:1')
        print(f'\ncontrast_audit: {len(fails)} of {len(cases)} pairings below threshold.')
        return 1

    tokens = scan_light_tokens()
    if tokens:
        print('\ncontrast_audit: LIGHT-ONLY TOKENS used as a foreground')
        by_tok = {}
        for path, line, name in tokens:
            by_tok.setdefault(name, []).append(f'{path}:{line}')
        for name, sites in sorted(by_tok.items(), key=lambda kv: -len(kv[1])):
            print(f'  AppTheme.{name:18} {len(sites):>3} site(s)')
            for site in (sites if verbose else sites[:3]):
                print(f'      {site}')
            if not verbose and len(sites) > 3:
                print(f'      … {len(sites) - 3} more (--verbose to list)')
        print(f'\ncontrast_audit: {len(tokens)} light-only token use(s). '
              'These vanish in dark mode — use the context.* getters.')
        return 1

    fills = scan_fill_as_foreground()
    if fills:
        print('\ncontrast_audit: SURFACE TOKENS used as a foreground')
        for path, line, name, ctor in fills:
            print(f'  context.{name:14} in {ctor:10} {path}:{line}')
        print(f'\ncontrast_audit: {len(fills)} surface token(s) colouring '
              'text or an icon. A fill is the colour of the thing behind the '
              'text — use context.mutedText for secondary text, '
              'context.primaryText for body, context.decorativeInk for a '
              'decorative glyph.')
        return 1

    literals = scan_literals()
    if literals:
        print('\ncontrast_audit: FOREGROUND COLOUR LITERALS below 4.5:1')
        by_colour = {}
        for path, line, name, hexv, r in literals:
            by_colour.setdefault((name, hexv, r), []).append(f'{path}:{line}')
        for (name, hexv, r), sites in sorted(
                by_colour.items(), key=lambda kv: -len(kv[1])):
            shown = f'{r:5.2f}:1' if r else 'not theme-aware'
            print(f'  Colors.{name:18} {hexv:>11}  {shown:>15}  '
                  f'{len(sites):>3} site(s)')
            for site in sites[:3] if not verbose else sites:
                print(f'      {site}')
            if not verbose and len(sites) > 3:
                print(f'      … {len(sites) - 3} more (--verbose to list)')
        print(f'\ncontrast_audit: {len(literals)} literal(s) bypass the tokens '
              'and fail. Use the theme colours (colorScheme.onSurfaceVariant, '
              'AppTheme.hintColor, AppTheme.semanticFor) instead.')
        return 1

    print(f'\ncontrast_audit: all {len(cases)} pairings pass in both themes, '
          'and no failing colour literals in lib/.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
