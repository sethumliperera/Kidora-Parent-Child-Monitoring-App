import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

class CreateChildPage extends StatefulWidget {
  const CreateChildPage({super.key});

  @override
  State<CreateChildPage> createState() => _CreateChildPageState();
}

class _CreateChildPageState extends State<CreateChildPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _interestsController = TextEditingController();

  String? _selectedGender;
  File? _selectedImage;
  bool isLoading = false;
  Map<String, dynamic>? _newChild;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _interestsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> createChildAndGenerateCode() async {
    if (!_formKey.currentState!.validate() || _selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all required fields")),
      );
      return;
    }

    final name = _nameController.text.trim();
    final age = int.parse(_ageController.text.trim());
    final interests = _interestsController.text.trim();

    setState(() => isLoading = true);

    try {
      String? photoUrl;
      if (_selectedImage != null) {
        photoUrl = await ApiService.uploadPhoto(_selectedImage!);
      }

      final result = await ApiService.addChild(
        name: name,
        age: age,
        gender: _selectedGender,
        interests: interests,
        photoUrl: photoUrl,
      );

      if (mounted) {
        setState(() => _newChild = result['child']);
        _showPairingCodeDialog(result['linking_code']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to create child: $e")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
          'Create Child Profile',
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
                const SizedBox(height: 12),
                Text(
                  "Add your child details to generate a secure linking code.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : AppTheme.primaryColor)
                                .withValues(alpha: isDark ? 0.1 : 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? Colors.white24
                                  : AppTheme.primaryColor.withValues(alpha: 0.3),
                              width: 2,
                            ),
                            image: _selectedImage != null
                                ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                                : (_selectedGender != null && (_selectedGender == "Boy" || _selectedGender == "Girl"))
                                    ? DecorationImage(
                                        image: AssetImage(_selectedGender == "Boy" ? 'assets/icons/alex.png' : 'assets/icons/emma.png'),
                                        fit: BoxFit.cover)
                                    : null,
                          ),
                          child: _selectedImage == null && (_selectedGender == null || (_selectedGender != "Boy" && _selectedGender != "Girl"))
                               ? Icon(
                                   Icons.add_a_photo_rounded,
                                   size: 40,
                                   color: isDark
                                       ? Colors.white70
                                       : AppTheme.primaryColor.withValues(alpha: 0.7),
                                 )
                               : null,
                        ),
                        if (_selectedImage != null)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Icon(Icons.edit, color: Colors.indigo, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Tap to choose profile photo",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : AppTheme.lightTextSecondary,
                  ),
                ),

                const SizedBox(height: 32),

                GlassCard(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFieldLabel("Child's Name", isDark),
                        _buildTextField(
                          _nameController,
                          "Enter child's name",
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? "Name is required" : null,
                        ),

                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildFieldLabel("Age", isDark),
                                  _buildTextField(
                                    _ageController,
                                    "e.g. 12",
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    validator: (v) {
                                      final value = v?.trim() ?? "";
                                      final age = int.tryParse(value);
                                      if (value.isEmpty) return "Age required";
                                      if (age == null) return "Invalid age";
                                      if (age < 3 || age > 18) return "Age 3-18 only";
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildFieldLabel("Gender", isDark),
                                  _buildGenderSelector(isDark),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        _buildFieldLabel("Interests (Optional)", isDark),
                        _buildTextField(
                          _interestsController,
                          "e.g. Gaming, Music, Art",
                          maxLines: 2,
                        ),

                        const SizedBox(height: 40),

                        ElevatedButton(
                          onPressed: isLoading ? null : createChildAndGenerateCode,
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("Generate Pairing Code"),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, bool isDark) {
    final labelColor =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: labelColor,
          letterSpacing: 0.5,
        ),
      ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : AppTheme.primaryColor)
            .withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 1.2,
        ),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        inputFormatters: inputFormatters,
        style: TextStyle(
          color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: isDark ? Colors.white60 : AppTheme.lightTextSecondary,
          ),
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF69F0AE) : AppTheme.primaryColor,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildGenderSelector(bool isDark) {
    final genders = const ["Boy", "Girl", "Other"];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: genders.map((value) {
        final selected = _selectedGender == value;
        return ChoiceChip(
          label: Text(value),
          selected: selected,
          onSelected: (_) => setState(() => _selectedGender = value),
          selectedColor:
              (isDark ? const Color(0xFF69F0AE) : AppTheme.primaryColor)
                  .withValues(alpha: isDark ? 0.25 : 0.15),
          backgroundColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.5),
          labelStyle: TextStyle(
            color: selected
                ? (isDark ? const Color(0xFF69F0AE) : AppTheme.primaryColorDark)
                : (isDark ? Colors.white70 : AppTheme.lightTextSecondary),
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide(
            color: selected
                ? (isDark ? const Color(0xFF69F0AE) : AppTheme.primaryColor)
                : (isDark
                    ? Colors.white24
                    : AppTheme.lightBorder.withValues(alpha: 0.9)),
          ),
        );
      }).toList(),
    );
  }

  void _showPairingCodeDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;
        final width = MediaQuery.sizeOf(dialogContext).width;
        final padding = MediaQuery.paddingOf(dialogContext);
        final maxCardW = min(480.0, width - 32);

        final titleColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
        final bodyColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

        // High-contrast code panel (independent of frosted glass behind it).
        final codePanelBg = isDark ? const Color(0xFF0D1F15) : const Color(0xFFE8F5E9);
        final codeDigitColor = isDark ? const Color(0xFF69F0AE) : const Color(0xFF0D3D12);
        final codePanelBorder = const Color(0xFF69F0AE).withValues(alpha: isDark ? 0.45 : 0.5);
        final onCodeMetaColor =
            isDark ? const Color(0xFF9AE8B8) : const Color(0xFF1B5E20);

        void copyCode() {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Code copied to clipboard!"),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        return Center(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 8 + padding.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxCardW),
              child: GlassCard(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF69F0AE).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phonelink_setup_rounded,
                        color: Color(0xFF69F0AE),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Pairing Code",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Enter this code on your child's device to link it instantly.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Material(
                      color: codePanelBg,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: copyCode,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: codePanelBorder, width: 1.5),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  code.split('').join(' '),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    color: codeDigitColor,
                                    letterSpacing: 6,
                                    height: 1.1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.content_copy_rounded,
                                    size: 18,
                                    color: onCodeMetaColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      "Tap to copy",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: onCodeMetaColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          Navigator.pop(context, _newChild);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : AppTheme.primaryColor.withValues(alpha: 0.9),
                          foregroundColor:
                              isDark ? Colors.white : Colors.white,
                          minimumSize: const Size(double.infinity, 52),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white24
                                : AppTheme.primaryColorDark,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          "I've linked the device",
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().scale(
                    duration: 400.ms,
                    curve: Curves.easeOutBack,
                  ).fadeIn(),
            ),
          ),
        );
      },
    );
  }
}