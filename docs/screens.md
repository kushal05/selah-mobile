---

# 📱 Notes / Prayers / Promises App

## Flutter UI – Screen-by-Screen Replica

---

## 0️⃣ Base Design System (REQUIRED)

Create once. All screens depend on this.

```dart
// theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: Color(0xFF2D6CDF),
        secondary: Color(0xFF7B61FF),
        background: Color(0xFFF9F9F7),
        surface: Colors.white,
        onPrimary: Colors.white,
        onSurface: Color(0xFF1C1C1E),
      ),
      scaffoldBackgroundColor: Color(0xFFF9F9F7),
      textTheme: TextTheme(
        titleLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16),
        bodyMedium: TextStyle(fontSize: 14),
        labelMedium: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}
```

---

## 1️⃣ Home / Dashboard Screen

```dart
class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(current: 'Home'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Good Morning", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text("Wednesday, Oct 24", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              const DailyFocusCard(),
              const SizedBox(height: 24),
              const QuickActionsRow(),
              const SizedBox(height: 24),
              const OverviewGrid(),
            ],
          ),
        ),
      ),
    );
  }
}

class DailyFocusCard extends StatelessWidget {
  const DailyFocusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("DAILY FOCUS", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          const Text(
            "Prayer for Peace",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text("Scheduled for today", style: TextStyle(color: Colors.white70)),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
            ),
            onPressed: () {},
            child: const Text("Open Prayer"),
          )
        ],
      ),
    );
  }
}
```

---

## 2️⃣ Global Search Screen

```dart
class GlobalSearchScreen extends StatelessWidget {
  const GlobalSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: "Search",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SearchSection(
              title: "PEOPLE",
              children: const [
                SearchRow(
                  title: "Sarah Hopewell",
                  subtitle: "Small Group Member • Friend",
                )
              ],
            ),
            SearchSection(
              title: "PRAYERS",
              children: const [
                SearchRow(
                  title: "Praying for Hope in difficult times",
                  subtitle: "Active • Updated 2 days ago",
                ),
                SearchRow(
                  title: "Job opportunity for Hope Center",
                  subtitle: "Answered • Archived",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 3️⃣ Note Detail / Editor Screen

```dart
class NoteDetailScreen extends StatelessWidget {
  const NoteDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MetadataRow(),
              const SizedBox(height: 16),
              Text("The Meaning of Prayer",
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                "Prayer is not just asking for things, but a way to align our hearts with God's will.",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text("Key Points",
                  style: Theme.of(context).textTheme.titleMedium),
              const Bullet("Adoration: Praising God for who He is."),
              const Bullet("Confession: Admitting our shortcomings."),
              const Bullet("Thanksgiving: Gratitude for His blessings."),
              const Bullet("Supplication: Asking for our needs."),
              const SizedBox(height: 24),
              Text("Action Items",
                  style: Theme.of(context).textTheme.titleMedium),
              const CheckboxRow(label: "Read Psalms 23", checked: true),
              const CheckboxRow(label: "Journal about gratitude"),
              const CheckboxRow(label: "Pray for the small group"),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 4️⃣ Notes List Screen

```dart
class NotesHomeScreen extends StatelessWidget {
  const NotesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const BottomNav(current: "Notes"),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("All Notes", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              const FolderRow(title: "Sermons", count: 12),
              const FolderRow(title: "Bible Study", count: 5),
              const FolderRow(title: "Personal Reflections", count: 8),
              const SizedBox(height: 24),
              const NoteRow(
                  title: "Sunday Service: Grace and Truth",
                  date: "Oct 24",
                  tag: "Sermon"),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 5️⃣ People List Screen

```dart
class PeopleListScreen extends StatelessWidget {
  const PeopleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const BottomNav(current: "More"),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Text("People", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            PersonCard(name: "Sarah Miller", relation: "Sister"),
          ],
        ),
      ),
    );
  }
}
```

---

## 6️⃣ Person Detail Screen

```dart
class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const CircleAvatar(radius: 40),
              const SizedBox(height: 12),
              Text("Sarah Miller",
                  style: Theme.of(context).textTheme.titleLarge),
              const Text("Sister", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              const TagRow(tags: ["Family", "Salvation", "Priority"]),
              const SizedBox(height: 24),
              Text("Linked Prayers",
                  style: Theme.of(context).textTheme.titleMedium),
              const LinkedCard(
                  title: "Complete Healing", subtitle: "Logged 2 days ago"),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 7️⃣ Prayers Dashboard

```dart
class PrayersDashboardScreen extends StatelessWidget {
  const PrayersDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(current: "Prayers"),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Prayers", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text("Today's Focus",
                  style: Theme.of(context).textTheme.titleMedium),
              const PrayerFocusCard(title: "Family Health", frequency: "Daily"),
              const PrayerFocusCard(
                  title: "Wisdom at Work", frequency: "Weekdays"),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 8️⃣ Prayer Detail Screen

```dart
class PrayerDetailScreen extends StatelessWidget {
  const PrayerDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Expanded(
                    child: Text(
                      "Healing for Mom",
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ),
                  StatusChip(label: "Active"),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                "Praying for complete recovery after the surgery...",
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              const Text("Updates",
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const TimelineItem(
                  text: "Spoke to the doctor, inflammation is down.",
                  time: "Today, 9:30 AM"),
              const TimelineItem(
                  text: "Surgery went well.", time: "Oct 24, 4:00 PM"),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text("Log Prayer"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 9️⃣ Promise Detail Screen

```dart
class PromiseDetailScreen extends StatelessWidget {
  const PromiseDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Jeremiah 29:11",
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const TagRow(tags: ["Hope", "Future", "Provision"]),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "For I know the plans I have for you...",
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text("Conditions",
                  style: Theme.of(context).textTheme.titleMedium),
              const ConditionRow(
                  condition: "Seek Him with all your heart",
                  status: "MET"),
              const ConditionRow(
                  condition: "Pray continuously without ceasing",
                  status: "ACTIVE"),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 🔟 Promises List Screen

```dart
class PromisesListScreen extends StatelessWidget {
  const PromisesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const BottomNav(current: "Promises"),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Text("Promises",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            PromiseCard(
                reference: "Jeremiah 29:11",
                preview: "Plans to give you hope and a future"),
          ],
        ),
      ),
    );
  }
}
```