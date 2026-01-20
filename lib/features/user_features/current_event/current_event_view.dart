import 'package:flutter/material.dart';

class CurrentEventView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const CurrentEventView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  _CurrentEventViewState createState() => _CurrentEventViewState();
}


class _CurrentEventViewState extends State<CurrentEventView>{
  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Current Event", style: TextStyle(fontSize: 26)),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isLoading)
                  Icon(Icons.sync, color: Colors.blue)
                else if (widget.hasConnection)
                  Icon(Icons.check_circle, color: Colors.green)
                else
                  Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                if (widget.lastUpdated != null)
                  Text(
                    widget.hasConnection
                        ? 'Updated: ${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}'
                        : 'No connection · Last: ${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 12, color: widget.hasConnection ? Colors.grey : Colors.redAccent),
                  )
                else
                  Text(
                    'No data available',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
              ],
            ),
          ],
        )
,
      ),
    );
  }
}