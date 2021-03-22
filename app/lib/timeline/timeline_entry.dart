import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flare_flutter/flare.dart' as flare;
import 'package:flare_dart/animation/actor_animation.dart' as flare;
import 'package:flare_dart/math/aabb.dart' as flare;
import 'package:flare_dart/math/vec2d.dart' as flare;
import 'package:nima/nima.dart' as nima;
import 'package:nima/nima/animation/actor_animation.dart' as nima;
import 'package:nima/nima/math/aabb.dart' as nima;
import 'package:timeline/timeline/timeline.dart';

/// 表示从 timeline.json 加载的可渲染资产的对象。
///
/// 每个[TimelineAsset]都封装了所有相关的绘制属性，并维护了对其原始[TimelineEntry]的引用。
abstract class TimelineAsset {
  String filename;

  // 控制图片（资源）宽度
  double width;
  // 控制图片（资源）高度
  double height;

  double opacity = 0.0;
  double scale = 0.0;
  double scaleVelocity = 0.0;

  double y = 0.0;
  double velocity = 0.0;
  TimelineEntry entry;
}

/// 该资产还具有有关其动画的信息。
abstract class TimelineAnimatedAsset extends TimelineAsset {
  bool loop;
  double animationTime = 0.0;
  double offset = 0.0;
  double gap = 0.0;
}

/// 可渲染的图像。
class TimelineImage extends TimelineAsset {
  ui.Image image;
}

/// 尼玛（Nima）资产。
class TimelineNima extends TimelineAnimatedAsset {
  nima.FlutterActor actorStatic;
  nima.FlutterActor actor;
  nima.ActorAnimation animation;
  nima.AABB setupAABB;
}

/// A `Flare` Asset.
class TimelineFlare extends TimelineAnimatedAsset {
  flare.FlutterActorArtboard actorStatic;
  flare.FlutterActorArtboard actor;
  flare.ActorAnimation animation;

  /// Some Flare assets will have multiple idle animations (e.g. 'Humans'),
  /// others will have an intro&idle animation (e.g. 'Sun is Born').
  /// All this information is in `timeline.json` file, and it's de-serialized in the
  /// [Timeline.loadFromBundle()] method, called during startup.
  /// and custom-computed AABB bounds to properly position them in the timeline.
  flare.ActorAnimation intro;
  flare.ActorAnimation idle;
  List<flare.ActorAnimation> idleAnimations;
  flare.AABB setupAABB;
}

/// A label for [TimelineEntry].
enum TimelineEntryType {
  // 时代
  Era,

  // 事件
  Incident,
}

/// 时间轴中的每个条目都由该对象的一个实例表示。
/// 每个收藏夹，搜索结果和详细信息页面都将从对该对象的引用中获取信息。
///
/// 它们都在启动时由 [BlocProvider] 构造函数初始化。
class TimelineEntry {
  TimelineEntryType type;

  /// 用于计算在时间轴中为气泡绘制多少条线。
  int lineCount = 1;

  String _label;
  String articleFilename;
  String id;

  Color accent;

  /// Each entry constitues an element of a tree:
  /// eras are grouped into spanning eras and events are placed into the eras they belong to.
  TimelineEntry parent;
  List<TimelineEntry> children;

  /// All the timeline entries are also linked together to easily access the next/previous event.
  /// After a couple of seconds of inactivity on the timeline, a previous/next entry button will appear
  /// to allow the user to navigate faster between adjacent events.
  TimelineEntry next;
  TimelineEntry previous;

  /// [Timeline] 对象使用所有这些参数来正确定位当前条目。
  double start;
  double end;
  double y = 0.0;
  double endY = 0.0;
  double length = 0.0;
  double opacity = 0.0;
  double labelOpacity = 0.0;
  double targetLabelOpacity = 0.0;
  double delayLabel = 0.0;
  double targetAssetOpacity = 0.0;
  double delayAsset = 0.0;
  double legOpacity = 0.0;
  double labelY = 0.0;
  double labelVelocity = 0.0;
  double favoriteY = 0.0;
  bool isFavoriteOccluded = false;

  TimelineAsset asset;

  bool get isVisible {
    return opacity > 0.0;
  }

  String get label => _label;

  /// Some labels already have newline characters to adjust their alignment.
  /// Detect the occurrence and add information regarding the line-count.
  set label(String value) {
    _label = value;
    int start = 0;
    lineCount = 1;
    while (true) {
      start = _label.indexOf("\n", start);
      if (start == -1) {
        break;
      }
      lineCount++;
      start++;
    }
  }

  /// Pretty-printing for the entry date.
  String formatYearsAgo() {
    if (start > 0) {
      return start.round().toString();
    }
    return TimelineEntry.formatYears(start) + " Ago";
  }

  /// Debug information.
  @override
  String toString() {
    return "TIMELINE ENTRY: $label -($start,$end)";
  }

  /// Helper method.
  static String formatYears(double start) {
    String label;
    int valueAbs = start.round().abs();
    if (valueAbs > 1000000000) {
      double v = (valueAbs / 100000000.0).floorToDouble() / 10.0;

      label = (valueAbs / 1000000000)
              .toStringAsFixed(v == v.floorToDouble() ? 0 : 1) +
          " Billion";
    } else if (valueAbs > 1000000) {
      double v = (valueAbs / 100000.0).floorToDouble() / 10.0;
      label =
          (valueAbs / 1000000).toStringAsFixed(v == v.floorToDouble() ? 0 : 1) +
              " Million";
    } else if (valueAbs > 10000) // N.B. < 10,000
    {
      double v = (valueAbs / 100.0).floorToDouble() / 10.0;
      label =
          (valueAbs / 1000).toStringAsFixed(v == v.floorToDouble() ? 0 : 1) +
              " Thousand";
    } else {
      label = valueAbs.toStringAsFixed(0);
    }
    return label + " Years";
  }
}
