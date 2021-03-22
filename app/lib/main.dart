
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeline/bloc_provider.dart';
import 'package:timeline/colors.dart';
import 'package:timeline/main_menu/main_menu.dart';

const DRAW_IMAGE = false;

/// 该应用由[BlocProvider]包装。 这允许子窗口小部件访问整个层次结构中的其他组件，而无需传递这些引用。
class TimelineApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return BlocProvider(
      child: MaterialApp(
        title: 'History & Future of Everything',
        theme: ThemeData(
            backgroundColor: background, scaffoldBackgroundColor: background),
        home: MenuPage(),
      ),
      platform: Theme.of(context).platform,
    );
  }
}

class MenuPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: null, body: MainMenuWidget());
  }
}

void main() => runApp(TimelineApp());