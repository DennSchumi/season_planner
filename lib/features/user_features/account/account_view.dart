import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/features/base_admin_view.dart';
import 'package:season_planer/services/auth_service.dart';

import '../../../services/providers/user_provider.dart';

class AccountView extends StatefulWidget {
  const AccountView({super.key});

  @override
  _AccountViewState createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  void _logOut() {
    AuthService().logout();
    Navigator.pushReplacementNamed(context, '/login');
  }


  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    bool userIsAdmin = user!.flightSchools.any(
      (fs) => fs.adminUserIds.contains(user.id),
    );

    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Text(
              "Account",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 40),

            OutlinedButton(
              onPressed: () {},
              child: const Text("Manage Flight School Memberships"),
            ),

            const SizedBox(height: 10),

            OutlinedButton(
              onPressed: () {},
              child: const Text("Manage Personal Information"),
            ),

            const SizedBox(height: 10),

            if (userIsAdmin)
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BaseAdminView()),
                  );
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Switch to ADMIN-Mode"),
                    SizedBox(width: 8),
                    Icon(Icons.admin_panel_settings_outlined),
                  ],
                ),
              ),

            const Spacer(),

            TextButton(
              onPressed: _logOut,
              child: const Text(
                "Log out",
                style: TextStyle(
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
