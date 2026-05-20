import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';

import '../services/api.dart';
import '../utils/child_identity.dart';

class SendRemindersPage extends StatefulWidget {
  final Map<String, dynamic>? child;
  const SendRemindersPage({super.key, this.child});

  @override
  State<SendRemindersPage> createState() => _SendRemindersPageState();
}

class _SendRemindersPageState extends State<SendRemindersPage> {
  String selectedType = 'Study Time';
  String priority = 'Normal';
  final TextEditingController _messageController = TextEditingController();
  bool _isLoading = false;

  TimeOfDay _selectedTime = TimeOfDay.now();
  String _repeatFrequency = 'Once';
  final List<String> _repeatOptions = ['Once', 'Daily', 'Weekly'];

  void _selectTime(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext builderContext) {
        return Container(
          height: 300,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(builderContext),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(builderContext),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: AppTheme.primaryColorDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: isDark ? Brightness.dark : Brightness.light,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: false,
                      initialDateTime: DateTime(
                        2000,
                        1,
                        1,
                        _selectedTime.hour,
                        _selectedTime.minute,
                      ),
                      onDateTimeChanged: (DateTime newDateTime) {
                        setState(() {
                          _selectedTime = TimeOfDay(
                            hour: newDateTime.hour,
                            minute: newDateTime.minute,
                          );
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectRepeat(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int initialIndex = _repeatOptions.indexOf(_repeatFrequency);
    if (initialIndex == -1) initialIndex = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext builderContext) {
        return Container(
          height: 250,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(builderContext),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(builderContext),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: AppTheme.primaryColorDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: isDark ? Brightness.dark : Brightness.light,
                    ),
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(
                        initialItem: initialIndex,
                      ),
                      onSelectedItemChanged: (int index) {
                        setState(() {
                          _repeatFrequency = _repeatOptions[index];
                        });
                      },
                      children: _repeatOptions.map((String option) {
                        return Center(
                          child: Text(
                            option,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.lightTextPrimary,
                              fontSize: 18,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 22,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Send Reminders',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ModernBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                _buildSectionHeader("Choose Reminder Type"),
                const SizedBox(height: 16),

                // Reminder Type (Glassmorphism)
                RadioGroup<String>(
                  groupValue: selectedType,
                  onChanged: (value) {
                    if (value != null) setState(() => selectedType = value);
                  },
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        _buildRadioTile("Study Time", Icons.book_outlined),
                        _buildRadioTile("Break Time", Icons.coffee_outlined),
                        _buildRadioTile("Sleep Time", Icons.bedtime_outlined),
                        _buildRadioTile("Custom", Icons.edit_note_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                _buildSectionHeader("Reminder Message"),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: "e.g. Time to finish your homework!",
                    hintStyle: TextStyle(
                      color:
                          isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    ),
                    prefixIcon: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 20,
                      color:
                          isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : AppTheme.primaryColor.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader("Set Time"),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => _selectTime(context),
                            child: _buildPickerTile(
                              _selectedTime.format(context),
                              Icons.access_time_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader("Repeat"),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => _selectRepeat(context),
                            child: _buildPickerTile(
                              _repeatFrequency,
                              Icons.repeat_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                _buildSectionHeader("Priority"),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildPriorityChip("Normal"),
                    const SizedBox(width: 16),
                    _buildPriorityChip("Urgent"),
                  ],
                ),

                const SizedBox(height: 80),

                ElevatedButton(
                  onPressed: _isLoading ? null : _sendReminder,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Send Reminder"),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendReminder() async {
    if (widget.child == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No child selected")));
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter a message")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final childId = parseChildDatabaseId(widget.child!['id']);
      if (childId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Invalid child profile. Go back and select a child again."),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      // Build schedule for today and block if time has already passed.
      final now = DateTime.now();
      final scheduledDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      if (!scheduledDateTime.isAfter(now)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please select a future time."),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      await ApiService.sendReminder(
        childId,
        message,
        title: selectedType,
        priority: priority,
        frequency: _repeatFrequency,
        scheduledAt: scheduledDateTime.toUtc().toIso8601String(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reminder sent successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back after sending
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to send reminder: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildRadioTile(String title, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = selectedType == title;

    return GestureDetector(
      onTap: () => setState(() => selectedType = title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? AppTheme.primaryColorDark.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppTheme.primaryColorDark
                  : (isDark ? Colors.white70 : AppTheme.lightTextSecondary),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  fontSize: 16,
                ),
              ),
            ),
            Radio<String>(
              value: title,
              activeColor: AppTheme.primaryColorDark,
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppTheme.primaryColorDark;
                }
                return isDark ? Colors.white70 : AppTheme.lightTextSecondary;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerTile(String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
            ),
          ),
          Icon(icon, size: 18, color: AppTheme.primaryColorDark),
        ],
      ),
    );
  }

  Widget _buildPriorityChip(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSelected = priority == label;
    bool isUrgent = label.toLowerCase() == 'urgent';

    Color activeColor = isUrgent
        ? Colors.red.withValues(alpha: 0.3)
        : AppTheme.primaryColor.withValues(alpha: 0.3);
    Color activeBorderColor =
        isUrgent ? Colors.redAccent : AppTheme.primaryColorLight;
    Color activeTextColor = isUrgent ? Colors.white : Colors.white;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => priority = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color:
                isSelected ? activeColor : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? activeBorderColor : Colors.white,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected
                  ? activeTextColor
                  : (isDark ? Colors.white : AppTheme.lightTextPrimary),
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}