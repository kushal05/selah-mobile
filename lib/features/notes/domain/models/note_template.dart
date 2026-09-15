import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'block_type.dart';
import 'editor_block.dart';
import 'editor_document.dart';
import 'note.dart';

/// Built-in note templates. Each template knows how to seed a [Note] with a
/// suggested title and a starter document of blocks so the user isn't
/// staring at a blank page.
///
/// Templates are deliberately small (3–8 blocks). They're scaffolding, not
/// content; users edit freely from the seed.
class NoteTemplate {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String defaultTitle;
  final List<EditorBlock> Function() blocksBuilder;

  const NoteTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.defaultTitle,
    required this.blocksBuilder,
  });

  /// Build a fresh [Note] seeded from this template. Each invocation creates
  /// new block IDs so the same template can be used multiple times.
  Note buildNote({String? id, String? folderId}) {
    return Note.create(
      id: id ?? const Uuid().v4(),
      title: defaultTitle,
      document: EditorDocument(blocks: blocksBuilder()),
    ).copyWith(folderId: folderId);
  }
}

EditorBlock _paragraph(String text) => EditorBlock(
      id: const Uuid().v4(),
      type: BlockType.paragraph,
      content: text,
    );

EditorBlock _heading(int level, String text) => EditorBlock(
      id: const Uuid().v4(),
      type: level == 1
          ? BlockType.heading1
          : level == 2
              ? BlockType.heading2
              : BlockType.heading3,
      content: text,
    );

EditorBlock _bullet(String text) => EditorBlock(
      id: const Uuid().v4(),
      type: BlockType.bulletList,
      content: text,
    );

EditorBlock _check(String text) => EditorBlock(
      id: const Uuid().v4(),
      type: BlockType.checkbox,
      content: text,
      isChecked: false,
    );

/// The set of built-in templates. Order is the order shown in the picker.
final List<NoteTemplate> builtInNoteTemplates = [
  NoteTemplate(
    id: 'blank',
    name: 'Blank Note',
    description: 'Start from scratch.',
    icon: Icons.insert_drive_file_outlined,
    // Empty, so the title field shows its placeholder and the user names the
    // note themselves. A pre-filled 'Untitled Note' is a word they have to
    // delete before they can write their own, and one they will often leave.
    defaultTitle: '',
    blocksBuilder: () => [EditorBlock.paragraph()],
  ),
  NoteTemplate(
    id: 'sermon-notes',
    name: 'Sermon Notes',
    description: 'Passage, key points, what to do next.',
    icon: Icons.record_voice_over_outlined,
    defaultTitle: 'Sermon Notes',
    // No 'Speaker' section: the note already has a Preacher field in Note
    // Details, which links to a real person record. Repeating it in the body
    // stores the name twice, and the copy in the body is the one that cannot
    // be searched, filtered or linked.
    blocksBuilder: () => [
      _heading(2, 'Passage'),
      _paragraph(''),
      _heading(2, 'Key points'),
      _bullet(''),
      // The prompt belongs in the heading. As the checkbox's own text it
      // became the task — leaving the user a tick-box that reads 'One thing
      // I will do this week' rather than the thing they decided to do.
      _heading(2, 'Application — one thing I will do this week'),
      _check(''),
    ],
  ),
  NoteTemplate(
    id: 'prayer-journal',
    name: 'Prayer Journal',
    description: 'Gratitude, requests, listening.',
    icon: Icons.volunteer_activism_outlined,
    defaultTitle: 'Prayer Journal',
    blocksBuilder: () => [
      _heading(2, 'Gratitude'),
      _bullet(''),
      _heading(2, 'Requests'),
      _bullet(''),
      _heading(2, 'Listening'),
      _paragraph(''),
    ],
  ),
  NoteTemplate(
    id: 'bible-study',
    name: 'Bible Study',
    description: 'Observe, interpret, apply.',
    icon: Icons.menu_book_outlined,
    defaultTitle: 'Bible Study',
    blocksBuilder: () => [
      _heading(2, 'Passage'),
      _paragraph(''),
      _heading(2, 'Observation — what does it say?'),
      _bullet(''),
      _heading(2, 'Interpretation — what does it mean?'),
      _bullet(''),
      _heading(2, 'Application — what will I do?'),
      _check(''),
    ],
  ),
  NoteTemplate(
    id: 'examen',
    name: 'Daily Examen',
    description: 'Five-movement Ignatian reflection.',
    icon: Icons.nights_stay_outlined,
    defaultTitle: 'Examen',
    blocksBuilder: () => [
      _heading(2, '1. Gratitude'),
      _paragraph(''),
      _heading(2, '2. Ask for light'),
      _paragraph(''),
      _heading(2, '3. Review the day'),
      _paragraph(''),
      _heading(2, '4. Face your shortcomings'),
      _paragraph(''),
      _heading(2, '5. Look toward tomorrow'),
      _paragraph(''),
    ],
  ),
  NoteTemplate(
    id: 'gratitude',
    name: 'Gratitude List',
    description: 'Three things you are thankful for.',
    icon: Icons.favorite_outline,
    defaultTitle: 'Gratitude',
    blocksBuilder: () => [
      // A heading, not a paragraph: as body text the prompt was content the
      // user had to delete, and it read as though they had written it.
      _heading(2, 'Today I am thankful for'),
      _bullet(''),
      _bullet(''),
      _bullet(''),
    ],
  ),
];
