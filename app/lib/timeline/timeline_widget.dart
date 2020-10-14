import 'dart:ui';

import 'package:flare_flutter/flare_actor.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:timeline/article/article_widget.dart';
import 'package:timeline/bloc_provider.dart';
import "package:timeline/colors.dart";
import 'package:timeline/main_menu/menu_data.dart';
import 'package:timeline/timeline/timeline.dart';
import 'package:timeline/timeline/timeline_entry.dart';
import 'package:timeline/timeline/timeline_render_widget.dart';
import 'package:timeline/timeline/timeline_utils.dart';

// typedef ShowMenuCallback();
// typedef SelectItemCallback(TimelineEntry item);

///这是与时间轴对象关联的有状态窗口小部件。
///它是从 [focusItem] 构建的，这是 [Timeline] 创建时应关注的事件。
class TimelineWidget extends StatefulWidget {
  final MenuItemData focusItem;
  final Timeline timeline;
  TimelineWidget(this.focusItem, this.timeline, {Key key}) : super(key: key);

  @override
  _TimelineWidgetState createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  static const String DefaultEraName = "Birth of the Universe";
  static const double TopOverlap = 56.0;

  /// 如 [_scaleStart]，[_ scaleUpdate]，[_ scaleEnd]中所述，在执行缩放操作时，
  /// 这些变量用于计算时间轴的正确视口。
  Offset _lastFocalPoint;
  double _scaleStartYearStart = -100.0;
  double _scaleStartYearEnd = 100.0;

  /// 当触摸[时间轴]上的气泡时，请跟踪已触摸哪个元素以便移至[article_widget]。
  TapTarget _touchedBubble;
  TimelineEntry _touchedEntry;

  /// 时间轴目前关注哪个时代。 默认为 [DefaultEraName]。
  String _eraName;

  /// 语法糖获取器
  Timeline get timeline => widget.timeline;

  Color _headerTextColor;
  Color _headerBackgroundColor;

  /// 此状态变量可切换左侧边栏的呈现，以显示时间轴上已有的收藏夹元素。
  bool _showFavorites = false;

  /// 以下三个函数定义为
  /// [GestureDetector]小部件在呈现此小部件时。
  /// 首先收集有关缩放操作起点的信息。
  /// 然后根据传入的[ ScaleUpdateDetails] 数据执行更新，并将相关信息传递到 [Timeline]，
  /// 以便它可以正确显示所有相关信息。
  void _scaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.focalPoint;
    _scaleStartYearStart = timeline.start;
    _scaleStartYearEnd = timeline.end;
    timeline.isInteracting = true;
    timeline.setViewport(velocity: 0.0, animate: true);
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    double changeScale = details.scale;
    double scale =
        (_scaleStartYearEnd - _scaleStartYearStart) / context.size.height;

    double focus = _scaleStartYearStart + details.focalPoint.dy * scale;
    double focalDiff =
        (_scaleStartYearStart + _lastFocalPoint.dy * scale) - focus;
    timeline.setViewport(
        start: focus + (_scaleStartYearStart - focus) / changeScale + focalDiff,
        end: focus + (_scaleStartYearEnd - focus) / changeScale + focalDiff,
        height: context.size.height,
        animate: true);
  }

  void _scaleEnd(ScaleEndDetails details) {
    timeline.isInteracting = false;
    timeline.setViewport(
        velocity: details.velocity.pixelsPerSecond.dy, animate: true);
  }

  ///以下两个回调传递给 [TimelineRenderWidget]，因此可以将信息传递回此小部件。
  onTouchBubble(TapTarget bubble) {
    _touchedBubble = bubble;
  }

  onTouchEntry(TimelineEntry entry) {
    _touchedEntry = entry;
  }

  void _tapDown(TapDownDetails details) {
    timeline.setViewport(velocity: 0.0, animate: true);
  }

  /// 如果 [TimelineRenderWidget] 已将 [_touchedBubble] 设置为时间线上当前触摸的气泡，则从屏
  /// 幕上移开手指后，应用程序将检查触摸操作是否包含缩放操作。 如果是这样，请相应地调整布局。 否则，
  /// 触发点击的气泡的[Navigator.push]。 这会将应用程序移至 [ArticleWidget]。
  void _tapUp(TapUpDetails details) {
    EdgeInsets devicePadding = MediaQuery.of(context).padding;
    if (_touchedBubble != null) {
      if (_touchedBubble.zoom) {
        MenuItemData target = MenuItemData.fromEntry(_touchedBubble.entry);

        timeline.padding = EdgeInsets.only(
            top: TopOverlap +
                devicePadding.top +
                target.padTop +
                Timeline.Parallax,
            bottom: target.padBottom);
        timeline.setViewport(
            start: target.start, end: target.end, animate: true, pad: true);
      } else {
        widget.timeline.isActive = false;

        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (BuildContext context) =>
                    ArticleWidget(article: _touchedBubble.entry)))
            .then((v) => widget.timeline.isActive = true);
      }
    } else if (_touchedEntry != null) {
      MenuItemData target = MenuItemData.fromEntry(_touchedEntry);

      timeline.padding = EdgeInsets.only(
          top: TopOverlap +
              devicePadding.top +
              target.padTop +
              Timeline.Parallax,
          bottom: target.padBottom);
      timeline.setViewport(
          start: target.start, end: target.end, animate: true, pad: true);
    }
  }

  /// 当执行长按操作时，将调整视口，以便根据[TimelineEntry]信息更新可见的开始时间和结束时间。
  /// 长按的气泡将漂浮到视口的顶部，并且视口将适当缩放。
  void _longPress() {
    EdgeInsets devicePadding = MediaQuery.of(context).padding;
    if (_touchedBubble != null) {
      MenuItemData target = MenuItemData.fromEntry(_touchedBubble.entry);

      timeline.padding = EdgeInsets.only(
          top: TopOverlap +
              devicePadding.top +
              target.padTop +
              Timeline.Parallax,
          bottom: target.padBottom);
      timeline.setViewport(
          start: target.start, end: target.end, animate: true, pad: true);
    }
  }

  @override
  initState() {
    super.initState();
    if (timeline != null) {
      widget.timeline.isActive = true;
      _eraName = timeline.currentEra != null
          ? timeline.currentEra.label
          : DefaultEraName;
      timeline.onHeaderColorsChanged = (Color background, Color text) {
        setState(() {
          _headerTextColor = text;
          _headerBackgroundColor = background;
        });
      };
      /// 更新[时间轴]对象的标签。
      timeline.onEraChanged = (TimelineEntry entry) {
        setState(() {
          _eraName = entry != null ? entry.label : DefaultEraName;
        });
      };

      _headerTextColor = timeline.headerTextColor;
      _headerBackgroundColor = timeline.headerBackgroundColor;
      _showFavorites = timeline.showFavorites;
    }
  }

  /// 更新当前视图并更改时间轴标题，颜色和背景色，
  @override
  void didUpdateWidget(covariant TimelineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (timeline != oldWidget.timeline && timeline != null) {
      setState(() {
        _headerTextColor = timeline.headerTextColor;
        _headerBackgroundColor = timeline.headerBackgroundColor;
      });

      timeline.onHeaderColorsChanged = (Color background, Color text) {
        setState(() {
          _headerTextColor = text;
          _headerBackgroundColor = background;
        });
      };
      timeline.onEraChanged = (TimelineEntry entry) {
        setState(() {
          _eraName = entry != null ? entry.label : DefaultEraName;
        });
      };
      setState(() {
        _eraName =
            timeline.currentEra != null ? timeline.currentEra : DefaultEraName;
        _showFavorites = timeline.showFavorites;
      });
    }
  }

  /// 这是 [StatefulWidget] 生命周期方法。 这里已被覆盖，因此我们可以正确地更新 [Timeline] 小部件。
  @override
  deactivate() {
    super.deactivate();
    if (timeline != null) {
      timeline.onHeaderColorsChanged = null;
      timeline.onEraChanged = null;
    }
  }

  /// 此小部件包装在[Scaffold]中，具有经典的Material Design视觉布局结构。
  /// 然后，应用程序的主体由[GestureDetector]组成，可以正确处理所有用户输入的事件。
  /// 然后，此小部件放置一个[Stack]：
  /// -[TimelineRenderWidget]渲染时间线的实际内容，例如当前可见的气泡及其对应的[FlareWidget]，左侧的刻度线等。
  /// -[BackdropFilter]，它包装顶部标题栏，并带有“后退”按钮，“收藏夹”按钮及其颜色。
  @override
  Widget build(BuildContext context) {
    EdgeInsets devicePadding = MediaQuery.of(context).padding;
    if (timeline != null) {
      timeline.devicePadding = devicePadding;
    }
    return Scaffold(
      backgroundColor: Colors.greenAccent,
      body: GestureDetector(
          onLongPress: _longPress,
          onTapDown: _tapDown,
          onScaleStart: _scaleStart,
          onScaleUpdate: _scaleUpdate,
          onScaleEnd: _scaleEnd,
          onTapUp: _tapUp,
          child: Stack(children: <Widget>[
            TimelineRenderWidget(
                timeline: timeline,
                favorites: BlocProvider.favorites(context).favorites,
                topOverlap: TopOverlap + devicePadding.top,
                focusItem: widget.focusItem,
                touchBubble: onTouchBubble,
                touchEntry: onTouchEntry),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                      height: devicePadding.top,
                      color: _headerBackgroundColor != null
                          ? _headerBackgroundColor
                          : Color.fromRGBO(238, 240, 242, 0.81)),
                  Container(
                      color: _headerBackgroundColor != null
                          ? _headerBackgroundColor
                          : Color.fromRGBO(238, 240, 242, 0.81),
                      height: 56.0,
                      width: double.infinity,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            IconButton(
                              padding:
                                  EdgeInsets.only(left: 20.0, right: 20.0),
                              color: _headerTextColor != null
                                  ? _headerTextColor
                                  : Colors.black.withOpacity(0.5),
                              alignment: Alignment.centerLeft,
                              icon: Icon(Icons.arrow_back),
                              onPressed: () {
                                widget.timeline.isActive = false;
                                Navigator.pop(context);
                                return true;
                              },
                            ),
                            Text(
                              _eraName,
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                  fontFamily: "RobotoMedium",
                                  fontSize: 20.0,
                                  color: _headerTextColor != null
                                      ? _headerTextColor
                                      : darkText.withOpacity(
                                          darkText.opacity * 0.75)),
                            ),
                            Expanded(
                                child: GestureDetector(
                                    child: Transform.translate(
                                        offset: const Offset(0.0, 0.0),
                                        child: Container(
                                          height: 60.0,
                                          width: 60.0,
                                          padding: EdgeInsets.all(18.0),
                                          color:
                                              Colors.white.withOpacity(0.0),
                                          child: FlareActor(
                                              "assets/heart_toolbar.flr",
                                              animation: _showFavorites
                                                  ? "On"
                                                  : "Off",
                                              shouldClip: false,
                                              color: _headerTextColor !=
                                                      null
                                                  ? _headerTextColor
                                                  : darkText.withOpacity(
                                                      darkText.opacity *
                                                          0.75),
                                              alignment:
                                                  Alignment.centerRight),
                                        )),
                                    onTap: () {
                                      timeline.showFavorites =
                                          !timeline.showFavorites;
                                      setState(() {
                                        _showFavorites =
                                            timeline.showFavorites;
                                      });
                                    })),
                          ]))
                ])
          ])),
    );
  }
}
