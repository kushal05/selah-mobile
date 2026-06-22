"""
Script to generate a PDF showcasing the features of the Notify application.
"""

from fpdf import FPDF
import os

class NotifyFeaturesPDF(FPDF):
    def __init__(self):
        super().__init__()
        self.set_auto_page_break(auto=True, margin=20)

    def header(self):
        if self.page_no() > 1:
            self.set_font('Helvetica', 'I', 9)
            self.set_text_color(128, 128, 128)
            self.cell(0, 10, 'Notify - Feature Overview', align='L')
            self.ln(5)
            self.set_draw_color(200, 200, 200)
            self.line(10, 15, 200, 15)
            self.ln(10)

    def footer(self):
        self.set_y(-15)
        self.set_font('Helvetica', 'I', 8)
        self.set_text_color(128, 128, 128)
        self.cell(0, 10, f'Page {self.page_no()}', align='C')

    def chapter_title(self, title):
        self.set_font('Helvetica', 'B', 18)
        self.set_text_color(45, 108, 223)  # Primary color #2D6CDF
        self.cell(0, 15, title, ln=True)
        self.ln(5)

    def section_title(self, title):
        self.set_font('Helvetica', 'B', 14)
        self.set_text_color(60, 60, 60)
        self.cell(0, 10, title, ln=True)
        self.ln(2)

    def subsection_title(self, title):
        self.set_font('Helvetica', 'B', 11)
        self.set_text_color(80, 80, 80)
        self.cell(0, 8, title, ln=True)
        self.ln(1)

    def body_text(self, text):
        self.set_font('Helvetica', '', 10)
        self.set_text_color(50, 50, 50)
        self.multi_cell(0, 6, text)
        self.ln(3)

    def bullet_point(self, text, indent=10):
        self.set_font('Helvetica', '', 10)
        self.set_text_color(50, 50, 50)
        x_start = 10 + indent
        self.set_x(x_start)
        self.cell(5, 6, chr(149))  # Bullet character
        available_width = 190 - indent - 5  # Page width minus margins and bullet
        self.multi_cell(available_width, 6, text)

    def screenshot_placeholder(self, caption, width=120, height=80):
        """Add a placeholder box for screenshots"""
        x = (210 - width) / 2  # Center horizontally
        self.set_x(x)

        # Draw placeholder box
        self.set_draw_color(200, 200, 200)
        self.set_fill_color(245, 245, 245)
        self.rect(x, self.get_y(), width, height, 'DF')

        # Add placeholder text
        self.set_xy(x, self.get_y() + height/2 - 5)
        self.set_font('Helvetica', 'I', 10)
        self.set_text_color(150, 150, 150)
        self.cell(width, 10, '[Screenshot: ' + caption + ']', align='C')

        self.set_y(self.get_y() + height/2 + 10)

        # Add caption
        self.set_font('Helvetica', 'I', 9)
        self.set_text_color(100, 100, 100)
        self.cell(0, 6, caption, align='C', ln=True)
        self.ln(8)

    def add_feature_box(self, title, description):
        """Add a highlighted feature box"""
        self.set_fill_color(240, 245, 255)
        self.set_draw_color(45, 108, 223)

        # Calculate height based on content
        self.set_font('Helvetica', 'B', 10)

        y_start = self.get_y()
        self.set_x(15)
        self.rect(15, y_start, 180, 25, 'DF')

        self.set_xy(20, y_start + 3)
        self.set_text_color(45, 108, 223)
        self.cell(0, 6, title, ln=True)

        self.set_x(20)
        self.set_font('Helvetica', '', 9)
        self.set_text_color(60, 60, 60)
        self.multi_cell(170, 5, description)

        self.set_y(y_start + 28)


def create_pdf():
    pdf = NotifyFeaturesPDF()

    # =====================
    # COVER PAGE
    # =====================
    pdf.add_page()
    pdf.ln(60)

    # App title
    pdf.set_font('Helvetica', 'B', 36)
    pdf.set_text_color(45, 108, 223)
    pdf.cell(0, 20, 'Notify', align='C', ln=True)

    # Subtitle
    pdf.set_font('Helvetica', '', 16)
    pdf.set_text_color(100, 100, 100)
    pdf.cell(0, 10, 'Personal Spiritual Development App', align='C', ln=True)
    pdf.ln(10)

    # Version
    pdf.set_font('Helvetica', 'I', 12)
    pdf.set_text_color(150, 150, 150)
    pdf.cell(0, 8, 'Version 0.1.0', align='C', ln=True)
    pdf.ln(30)

    # Brief description
    pdf.set_font('Helvetica', '', 11)
    pdf.set_text_color(80, 80, 80)
    pdf.set_x(30)
    pdf.multi_cell(150, 7,
        'A comprehensive Flutter application designed for personal reflection, '
        'spiritual tracking, and organized note-taking. Manage your prayers, '
        'track biblical promises, organize sermon notes, and stay connected '
        'with the people in your spiritual journey.',
        align='C')

    pdf.ln(40)
    pdf.set_font('Helvetica', 'I', 10)
    pdf.set_text_color(150, 150, 150)
    pdf.cell(0, 8, 'Feature Overview Document', align='C', ln=True)

    # =====================
    # TABLE OF CONTENTS
    # =====================
    pdf.add_page()
    pdf.chapter_title('Table of Contents')
    pdf.ln(5)

    toc_items = [
        ('1. Application Overview', 3),
        ('2. Home Dashboard', 4),
        ('3. Notes Module', 5),
        ('4. Prayers Module', 7),
        ('5. Promises Module', 9),
        ('6. People Directory', 10),
        ('7. Global Search', 11),
        ('8. Technical Architecture', 12),
    ]

    for item, page in toc_items:
        pdf.set_font('Helvetica', '', 11)
        pdf.set_text_color(50, 50, 50)
        pdf.cell(150, 8, item)
        pdf.cell(0, 8, str(page), align='R', ln=True)

    # =====================
    # APPLICATION OVERVIEW
    # =====================
    pdf.add_page()
    pdf.chapter_title('1. Application Overview')

    pdf.body_text(
        'Notify is a personal spiritual development application built with Flutter, '
        'designed to help users organize and track their spiritual journey. The app '
        'provides a comprehensive suite of tools for managing notes, prayers, biblical '
        'promises, and relationships with people in your spiritual community.'
    )

    pdf.section_title('Key Features at a Glance')
    pdf.bullet_point('Rich text note-taking with advanced formatting')
    pdf.bullet_point('Prayer tracking with status management (Active, Answered, Archived)')
    pdf.bullet_point('Biblical promises database with condition tracking')
    pdf.bullet_point('People directory for managing relationships')
    pdf.bullet_point('Global search across all content types')
    pdf.bullet_point('Offline-first architecture - all data stored locally')
    pdf.bullet_point('Material Design 3 with clean, modern UI')

    pdf.ln(5)
    pdf.section_title('Technology Stack')
    pdf.bullet_point('Framework: Flutter with Dart')
    pdf.bullet_point('State Management: Riverpod')
    pdf.bullet_point('Navigation: GoRouter with type-safe routing')
    pdf.bullet_point('Database: SQLite via Drift ORM')
    pdf.bullet_point('Design System: Material Design 3')

    pdf.ln(5)
    pdf.screenshot_placeholder('App Home Screen', 100, 160)

    # =====================
    # HOME DASHBOARD
    # =====================
    pdf.add_page()
    pdf.chapter_title('2. Home Dashboard')

    pdf.body_text(
        'The Home Dashboard serves as the main entry point of the application, '
        'providing users with a quick overview of their spiritual activities and '
        'easy access to all major features.'
    )

    pdf.section_title('Dashboard Components')

    pdf.subsection_title('Greeting & Date Display')
    pdf.body_text(
        'A personalized greeting with the current date helps users feel welcomed '
        'and oriented each time they open the app.'
    )

    pdf.subsection_title('Daily Focus Card')
    pdf.body_text(
        'Displays the most relevant item for today - whether it\'s a prayer reminder, '
        'a promise to meditate on, or an important note.'
    )

    pdf.subsection_title('Quick Action Shortcuts')
    pdf.body_text(
        'One-tap access to create new notes, add prayers, or log prayer activities '
        'without navigating through multiple screens.'
    )

    pdf.subsection_title('Overview Statistics Grid')
    pdf.body_text(
        'Visual cards showing key metrics: active prayers, answered prayers, '
        'total notes, and tracked promises.'
    )

    pdf.ln(3)
    pdf.screenshot_placeholder('Home Dashboard', 100, 160)

    pdf.add_feature_box(
        'Smart Exit Protection',
        'Double-tap back button to exit the app, with a helpful snackbar confirmation to prevent accidental exits.'
    )

    # =====================
    # NOTES MODULE
    # =====================
    pdf.add_page()
    pdf.chapter_title('3. Notes Module')

    pdf.body_text(
        'The Notes module is a powerful rich-text editor designed for capturing '
        'sermon notes, Bible study insights, and personal reflections. It features '
        'a block-based editing system that allows for structured, organized content.'
    )

    pdf.section_title('Rich Text Editor Features')

    pdf.subsection_title('Block Types')
    pdf.body_text('The editor supports seven different block types:')
    pdf.bullet_point('Headings (H1, H2, H3) - For organizing content hierarchy')
    pdf.bullet_point('Paragraphs - Standard text content')
    pdf.bullet_point('Bulleted Lists - With indentation up to 5 levels')
    pdf.bullet_point('Numbered Lists - Auto-numbered with proper sequencing')
    pdf.bullet_point('Checkbox Lists - For actionable items and tasks')

    pdf.ln(3)
    pdf.screenshot_placeholder('Notes Editor - Block Types', 100, 140)

    pdf.subsection_title('Text Formatting')
    pdf.body_text('Inline text formatting options include:')
    pdf.bullet_point('Bold - For emphasis and key points')
    pdf.bullet_point('Italic - For quotes and references')
    pdf.bullet_point('Underline - For important terms')
    pdf.bullet_point('Strikethrough - For completed or revised content')

    pdf.add_page()
    pdf.section_title('Note Organization')

    pdf.subsection_title('Folder Hierarchy')
    pdf.body_text(
        'Notes can be organized into folders with unlimited nesting depth, '
        'allowing for detailed categorization of content by topic, date, '
        'speaker, or any custom organization scheme.'
    )

    pdf.subsection_title('Note Metadata')
    pdf.body_text('Each note can include rich metadata:')
    pdf.bullet_point('Title - Required for all notes')
    pdf.bullet_point('Date - Associate notes with specific events (e.g., sermon date)')
    pdf.bullet_point('Preacher - Link notes to speakers')
    pdf.bullet_point('Tags - Flexible categorization system')

    pdf.ln(3)
    pdf.screenshot_placeholder('Notes List View', 100, 140)

    pdf.section_title('Editor Features')

    pdf.add_feature_box(
        'Auto-Save',
        'Notes are automatically saved as you type, with visual indicators showing save status (saving spinner vs. synced checkmark).'
    )

    pdf.ln(3)

    pdf.add_feature_box(
        'Undo/Redo',
        'Full operation history support allows you to undo and redo changes, providing confidence when editing.'
    )

    pdf.ln(3)

    pdf.add_feature_box(
        'Docked Formatting Toolbar',
        'The formatting toolbar stays docked above the keyboard for easy access to all formatting options while typing.'
    )

    # =====================
    # PRAYERS MODULE
    # =====================
    pdf.add_page()
    pdf.chapter_title('4. Prayers Module')

    pdf.body_text(
        'The Prayers module helps users maintain an organized prayer life by '
        'tracking prayer requests, logging prayer activities, and celebrating '
        'answered prayers. It provides a structured approach to prayer management.'
    )

    pdf.section_title('Prayer Dashboard')

    pdf.subsection_title('Today\'s Focus')
    pdf.body_text(
        'Highlights prayers that need attention today, helping users stay '
        'consistent in their prayer practice.'
    )

    pdf.subsection_title('Category Cards')
    pdf.body_text('Quick-access cards show prayer counts by status:')
    pdf.bullet_point('Active - Current, ongoing prayer requests')
    pdf.bullet_point('Answered - Prayers that have been fulfilled')
    pdf.bullet_point('Archived - Past prayers kept for reference')
    pdf.bullet_point('All Updates - Recent activity across all prayers')

    pdf.ln(3)
    pdf.screenshot_placeholder('Prayer Dashboard', 100, 160)

    pdf.section_title('Prayer Details')

    pdf.body_text('Each prayer includes comprehensive information:')
    pdf.bullet_point('Title and detailed description')
    pdf.bullet_point('Status indicator (Active, Answered, Archived)')
    pdf.bullet_point('Start date for tracking duration')
    pdf.bullet_point('Reminder settings')
    pdf.bullet_point('Update timeline showing prayer history')

    pdf.add_page()
    pdf.section_title('Prayer Actions')

    pdf.subsection_title('Log Prayer')
    pdf.body_text(
        'Quickly mark a prayer as prayed today. This creates a record of your '
        'prayer activity and helps maintain consistency.'
    )

    pdf.subsection_title('Add Update')
    pdf.body_text(
        'Record reflections, progress notes, or partial answers to prayers. '
        'Updates form a timeline showing the journey of each prayer.'
    )

    pdf.subsection_title('Mark as Answered')
    pdf.body_text(
        'Celebrate answered prayers by marking them complete. Answered prayers '
        'are preserved for encouragement and testimony.'
    )

    pdf.subsection_title('Link People')
    pdf.body_text(
        'Connect prayers to people from your directory. This creates meaningful '
        'relationships between your prayers and the people you pray for.'
    )

    pdf.ln(3)
    pdf.screenshot_placeholder('Prayer Detail View', 100, 160)

    # =====================
    # PROMISES MODULE
    # =====================
    pdf.add_page()
    pdf.chapter_title('5. Promises Module')

    pdf.body_text(
        'The Promises module serves as a personal database of biblical and '
        'spiritual promises. Users can store, reflect on, and track the '
        'conditions associated with God\'s promises.'
    )

    pdf.section_title('Promise Structure')

    pdf.body_text('Each promise entry contains:')
    pdf.bullet_point('Verse Reference - Scripture citation (e.g., Jeremiah 29:11)')
    pdf.bullet_point('Promise Text - The full promise content')
    pdf.bullet_point('Conditions - Requirements or contexts for the promise')
    pdf.bullet_point('Tags - For categorization and easy retrieval')
    pdf.bullet_point('Personal Notes - Your reflections and commentary')

    pdf.ln(3)
    pdf.screenshot_placeholder('Promises List', 100, 140)

    pdf.section_title('Condition Tracking')

    pdf.body_text(
        'Many biblical promises come with conditions. The app allows tracking '
        'of multiple conditions per promise:'
    )
    pdf.bullet_point('Condition Description - What the condition requires')
    pdf.bullet_point('Status - Track if conditions are fulfilled or ongoing')
    pdf.bullet_point('Commentary - Personal notes on each condition')

    pdf.ln(3)
    pdf.add_feature_box(
        'One-to-Many Relationships',
        'A single promise can have multiple conditions, each tracked independently with its own status and notes.'
    )

    pdf.ln(3)
    pdf.screenshot_placeholder('Promise Detail with Conditions', 100, 140)

    # =====================
    # PEOPLE DIRECTORY
    # =====================
    pdf.add_page()
    pdf.chapter_title('6. People Directory')

    pdf.body_text(
        'The People module provides a centralized directory for managing '
        'relationships with people in your spiritual community. It eliminates '
        'duplicate entries and enables meaningful connections across the app.'
    )

    pdf.section_title('Person Information')

    pdf.body_text('Each person entry includes:')
    pdf.bullet_point('Name - Full name of the person')
    pdf.bullet_point('Relation - Type of relationship (family, friend, church member)')
    pdf.bullet_point('Church Affiliation - Optional church or community association')
    pdf.bullet_point('Tags - For grouping and categorization')

    pdf.ln(3)
    pdf.screenshot_placeholder('People Directory', 100, 140)

    pdf.section_title('Cross-Feature Integration')

    pdf.body_text(
        'People can be linked to prayers, creating a powerful way to track '
        'who you\'re praying for. When you edit a person\'s information, '
        'it automatically updates across all linked prayers.'
    )

    pdf.add_feature_box(
        'No Duplicates',
        'The centralized people database ensures you never have duplicate entries. Link the same person to multiple prayers seamlessly.'
    )

    # =====================
    # GLOBAL SEARCH
    # =====================
    pdf.add_page()
    pdf.chapter_title('7. Global Search')

    pdf.body_text(
        'The Global Search feature provides comprehensive search capabilities '
        'across all content in the application, making it easy to find any '
        'information quickly.'
    )

    pdf.section_title('Search Capabilities')

    pdf.body_text('Search across all content types:')
    pdf.bullet_point('Notes - Search by title, content, or metadata')
    pdf.bullet_point('Prayers - Find by title, description, or status')
    pdf.bullet_point('People - Search by name or relation')
    pdf.bullet_point('Promises - Search by verse reference or text')

    pdf.ln(3)
    pdf.screenshot_placeholder('Global Search Results', 100, 140)

    pdf.section_title('Search Features')

    pdf.bullet_point('Real-time search results as you type')
    pdf.bullet_point('Results organized by category for easy browsing')
    pdf.bullet_point('Combined text and tag filtering')
    pdf.bullet_point('Quick navigation to search results')

    # =====================
    # TECHNICAL ARCHITECTURE
    # =====================
    pdf.add_page()
    pdf.chapter_title('8. Technical Architecture')

    pdf.section_title('Application Architecture')

    pdf.body_text(
        'Notify follows a feature-based clean architecture pattern, ensuring '
        'maintainability, testability, and scalability.'
    )

    pdf.subsection_title('Project Structure')
    pdf.set_font('Courier', '', 9)
    pdf.set_text_color(50, 50, 50)
    structure = """lib/
  core/
    database/    - SQLite database layer (Drift)
    navigation/  - GoRouter configuration
    theme/       - Material Design 3 theming
  features/
    home/        - Dashboard feature
    notes/       - Note-taking feature
    prayers/     - Prayer tracking feature
    promises/    - Promise management feature
    people/      - People directory feature
    search/      - Global search feature
  shared/
    widgets/     - Reusable UI components"""
    for line in structure.split('\n'):
        pdf.cell(0, 5, line, ln=True)
    pdf.ln(5)

    pdf.section_title('Navigation')
    pdf.body_text(
        'The app uses GoRouter for declarative, type-safe navigation with '
        'bottom tab-based navigation. Each tab maintains its own back stack '
        'for a native app-like experience.'
    )

    pdf.subsection_title('Navigation Tabs')
    pdf.bullet_point('Home - Dashboard and overview')
    pdf.bullet_point('Notes - Note management')
    pdf.bullet_point('Prayers - Prayer tracking')
    pdf.bullet_point('Promises - Promise database')
    pdf.bullet_point('More - People directory and settings')

    pdf.section_title('Data Persistence')

    pdf.body_text(
        'All data is stored locally using SQLite through the Drift ORM. '
        'The offline-first architecture ensures the app works without '
        'network connectivity.'
    )

    pdf.subsection_title('Database Features')
    pdf.bullet_point('Auto-save with debouncing')
    pdf.bullet_point('Version tracking for future sync capabilities')
    pdf.bullet_point('Efficient queries with Drift DAOs')
    pdf.bullet_point('JSON storage for complex document structures')

    pdf.section_title('Design System')

    pdf.body_text('The app uses a carefully crafted color palette:')
    pdf.bullet_point('Primary: #2D6CDF (Blue) - Main actions and highlights')
    pdf.bullet_point('Secondary: #7B61FF (Purple) - Accents')
    pdf.bullet_point('Surface: White - Cards and surfaces')
    pdf.bullet_point('Background: #F9F9F7 - Subtle gray background')

    # Save the PDF
    output_path = os.path.join(os.path.dirname(__file__), 'Notify_Features.pdf')
    pdf.output(output_path)
    print(f"PDF generated successfully: {output_path}")
    return output_path


if __name__ == "__main__":
    create_pdf()
