import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../utils/config.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // SIGN UP
  // Returns a map with 'user' (User?) and 'error' (String?)
  Future<Map<String, dynamic>> signUp(String email, String password) async {
    try {
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user != null) {
        // 📧 Send Email Verification (requested)
        await user.sendEmailVerification();
        debugPrint("Verification email sent to ${user.email}");
      }

      return {'user': user, 'error': null};
    } on FirebaseAuthException catch (e) {
      debugPrint("Signup Firebase Error: ${e.code} - ${e.message}");
      String errorMessage = "Signup failed. Try again.";

      switch (e.code) {
        case 'weak-password':
          errorMessage = "The password provided is too weak.";
          break;
        case 'email-already-in-use':
          errorMessage =
              "The email address is already in use by another account.";
          break;
        case 'invalid-email':
          errorMessage = "The email address is not valid.";
          break;
        case 'operation-not-allowed':
          errorMessage = "Email/password accounts are not enabled.";
          break;
      }
      return {'user': null, 'error': errorMessage};
    } catch (e) {
      debugPrint("Signup Error: $e");
      return {'user': null, 'error': e.toString()};
    }
  }

  // GOOGLE SIGN IN
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return {'user': null, 'error': 'Google sign-in cancelled.'};
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final user = userCredential.user;
      return {'user': user, 'error': null};
    } on FirebaseAuthException catch (e) {
      debugPrint('Google Login Firebase Error: ${e.code} - ${e.message}');
      String errorMessage = 'Google login failed. Please try again.';
      if (e.code == 'account-exists-with-different-credential') {
        errorMessage =
            'Account exists with different credentials. Use another sign-in method.';
      }
      return {'user': null, 'error': errorMessage};
    } catch (e) {
      debugPrint('Google Login Error: $e');
      return {'user': null, 'error': e.toString()};
    }
  }

  // LOGIN
  Future<User?> login(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential.user;
    } catch (e) {
      debugPrint("Login Error: $e");
      return null;
    }
  }

  // FORGOT PASSWORD - SEND RESET EMAIL
  Future<Map<String, dynamic>> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {
        'success': true,
        'message': 'Password reset email sent to $email',
      };
    } on FirebaseAuthException catch (e) {
      debugPrint('Password Reset Error: ${e.code} - ${e.message}');
      String errorMessage = 'Failed to send reset email. Try again.';
      if (e.code == 'user-not-found') {
        errorMessage = 'No account found with this email.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Invalid email address.';
      }
      return {'success': false, 'message': errorMessage};
    } catch (e) {
      debugPrint('Password Reset Error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // LOGOUT
  Future<void> logout() async {
    await _auth.signOut();
  }

  // DELETE ACCOUNT
  // Returns a message explaining the result
  Future<String?> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return "No user logged in";

      final uid = user.uid;

      // 1. Delete from Backend (Node.js)
      final response = await http.delete(
        Uri.parse("${Config.baseUrl}/users/$uid"),
      );

      if (response.statusCode == 200) {
        // 2. Delete from Firebase
        await user.delete();
        debugPrint("Firebase Account Deleted");
        return null; // Success
      } else {
        debugPrint(
          "Backend delete failed: Status ${response.statusCode}, Body: ${response.body}",
        );
        return "Backend deletion failed: ${response.body}";
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return "Please log out and log in again before deleting your account for security.";
      }
      return "Firebase Error: ${e.message}";
    } catch (e) {
      debugPrint("Delete Account Error: $e");
      return "An unexpected error occurred: $e";
    }
  }
}
