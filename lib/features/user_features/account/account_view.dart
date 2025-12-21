import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/features/base_admin_view.dart';
import 'package:season_planer/services/auth_service.dart';

import '../../../services/user_provider.dart';
import '../../admin_features/main_scaffold/main_admin_scaffold_view.dart';

class AccountView extends StatefulWidget {
  @override
  _AccountViewState createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  void _logOut() {
    AuthService().logout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  _switchToAdmin() {}

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    bool userIsAdmin = user!.flightSchools.any(
      (fs) => fs.adminUserIds.contains(user.id),
    );

    return Scaffold(
      body: SafeArea(
        minimum: EdgeInsets.all(10),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (userIsAdmin)
                OutlinedButton(
                  onPressed:
                      () => {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BaseAdminView(),
                          ),
                        ),
                      },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text("Switch to ADMIN-Mode"),
                      SizedBox(width: 8),
                      Icon(Icons.accessible_forward_outlined),
                    ],
                  ),
                ),
              const SizedBox(height: 50),
              TextButton(
                onPressed: _logOut,
                child: const Text(
                  "Ausloggen",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.blueAccent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
