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
    defaultTitle: 'Untitled Note',
    blocksBuilder: () => [EditorBlock.paragraph()],
  ),
  NoteTemplate(
    id: 'sermon-notes',
    name: 'Sermon Notes',
    description: 'Speaker, passage, key points, takeaways.',
    icon: Icons.record_voice_over_outlined,
    defaultTitle: 'Sermon Notes',
    blocksBuilder: () => [
      _heading(2, 'Speaker'),
      _paragraph(''),
      _heading(2, 'Passage'),
      _paragraph(''),
      _heading(2, 'Key Points'),
      _bullet(''),
      _heading(2, 'Application'),
      _check('One thing I will do this week'),
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
      _paragraph('Today I am thankful for…'),
      _bullet(''),
      _bullet(''),
      _bullet(''),
    ],
  ),
];
