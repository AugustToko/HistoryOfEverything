import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flare_flutter/flare.dart' as flare;
import 'package:flare_dart/animation/actor_animation.dart' as flare;
import 'package:flare_dart/math/aabb.dart' as flare;
import 'package:flare_dart/math/vec2d.dart' as flare;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:nima/nima.dart' as nima;
import 'package:nima/nima/actor_image.dart' as nima;
import 'package:nima/nima/animation/actor_animation.dart' as nima;
import 'package:nima/nima/math/aabb.dart' as nima;
import 'package:nima/nima/math/vec2d.dart' as nima;
import 'package:timeline/timeline/timeline_utils.dart';
import 'package:timeline/timeline/timeline_widget.dart';

import 'timeline_entry.dart';

typedef PaintCallback();
typedef ChangeEraCallback(TimelineEntry era);
typedef ChangeHeaderColorCallback(Color background, Color text);

class Timeline {
  /// Some aptly named constants for properly aligning the Timeline view.
  static const double LineWidth = 2.0;
  static const double LineSpacing = 10.0;
  static const double DepthOffset = LineSpacing + LineWidth;

  static const double EdgePadding = 8.0;
  static const double MoveSpeed = 10.0;
  static const double MoveSpeedInteracting = 40.0;
  static const double Deceleration = 3.0;
  static const double GutterLeft = 45.0;
  static const double GutterLeftExpanded = 75.0;

  static const double EdgeRadius = 4.0;
  static const double MinChildLength = 50.0;
  static const double BubbleHeight = 50.0;
  static const double BubbleArrowSize = 19.0;
  static const double BubblePadding = 20.0;
  static const double BubbleTextHeight = 20.0;
  static const double AssetPadding = 30.0;
  static const double Parallax = 100.0;
  static const double AssetScreenScale = 0.3;
  static const double InitialViewportPadding = 100.0;
  static const double TravelViewportPaddingTop = 400.0;

  static const double ViewportPaddingTop = 120.0;
  static const double ViewportPaddingBottom = 100.0;
  static const int SteadyMilliseconds = 500;

  /// The current platform is initialized at boot, to properly initialize
  /// [ScrollPhysics] based on the platform we're on.
  final TargetPlatform _platform;

  Timeline(this._platform) {
    setViewport(start: 1536.0, end: 3072.0);
  }

  /// 用于标记视口开始与结束位置
  double _start = 0.0; // 视口开始
  double _end = 0.0; //视口结束
  double _renderStart;
  double _renderEnd;
  double _lastFrameTime = 0.0;

  /// [TimelineWidget] 高度
  double _height = 0.0;
  double _firstOnScreenEntryY = 0.0;
  double _lastEntryY = 0.0;
  double _lastOnScreenEntryY = 0.0;
  double _offsetDepth = 0.0;
  double _renderOffsetDepth = 0.0;
  double _labelX = 0.0;
  double _renderLabelX = 0.0;
  double _lastAssetY = 0.0;
  double _prevEntryOpacity = 0.0;
  double _distanceToPrevEntry = 0.0;
  double _nextEntryOpacity = 0.0;
  double _distanceToNextEntry = 0.0;
  double _simulationTime = 0.0;
  double _timeMin = 0.0;
  double _timeMax = 0.0;
  double _gutterWidth = GutterLeft;

  bool _showFavorites = false;
  bool _isFrameScheduled = false;
  bool _isInteracting = false;
  bool _isScaling = false;
  bool _isActive = false;
  bool _isSteady = false;

  HeaderColors _currentHeaderColors;

  Color _headerTextColor;
  Color _headerBackgroundColor;

  /// Depending on the current [Platform], different values are initialized
  /// so that they behave properly on iOS&Android.
  ScrollPhysics _scrollPhysics;

  /// [_scrollPhysics] needs a [ScrollMetrics] value to function.
  ScrollMetrics _scrollMetrics;
  Simulation _scrollSimulation;

  /// 使得长按的气泡将漂浮到视口的顶部，并设置 padding，让气泡距离顶部有一段距离
  /// 见 [TimeLime.padding.png]
  EdgeInsets padding = EdgeInsets.zero;

  /// dart
  /// ```
  /// MediaQuery.of(context).padding
  /// ```
  EdgeInsets devicePadding = EdgeInsets.zero;

  Timer _steadyTimer;

  /// Through these two references, the Timeline can access the era and update
  /// the top label accordingly.
  TimelineEntry _currentEra;
  TimelineEntry _lastEra;

  /// These references allow to maintain a reference to the next and previous elements
  /// of the Timeline, depending on which elements are currently in focus.
  /// When there's enough space on the top/bottom, the Timeline will render a round button
  /// with an arrow to link to the next/previous element.
  TimelineEntry _nextEntry;
  TimelineEntry _renderNextEntry;
  TimelineEntry _prevEntry;
  TimelineEntry _renderPrevEntry;

  /// A gradient is shown on the background, depending on the [_currentEra] we're in.
  List<TimelineBackgroundColor> _backgroundColors;

  /// [Ticks] also have custom colors so that they are always visible with the changing background.
  List<TickColors> _tickColors;
  List<HeaderColors> _headerColors;

  /// All the [TimelineEntry]s that are loaded from disk at boot (in [loadFromBundle()]).
  List<TimelineEntry> _entries;

  /// The list of [TimelineAsset], also loaded from disk at boot.
  List<TimelineAsset> _renderAssets;

  Map<String, TimelineEntry> _entriesById = Map<String, TimelineEntry>();
  Map<String, nima.FlutterActor> _nimaResources =
      Map<String, nima.FlutterActor>();
  Map<String, flare.FlutterActor> _flareResources =
      Map<String, flare.FlutterActor>();

  /// 在添加对此对象的引用时，由 [TimelineRenderWidget] 设置的回调。
  /// 它将触发 [RenderBox.markNeedsPaint]。
  PaintCallback onNeedPaint;

  /// 接下来的两个回调绑定到 [TimelineWidget] 的状态设置，以便它可以更改顶部AppBar的外观。
  ChangeEraCallback onEraChanged;

  ChangeHeaderColorCallback onHeaderColorsChanged;

  double get renderOffsetDepth => _renderOffsetDepth;

  double get renderLabelX => _renderLabelX;

  double get start => _start;

  double get end => _end;

  double get renderStart => _renderStart;

  double get renderEnd => _renderEnd;

  double get gutterWidth => _gutterWidth;

  double get nextEntryOpacity => _nextEntryOpacity;

  double get prevEntryOpacity => _prevEntryOpacity;

  bool get isInteracting => _isInteracting;

  bool get showFavorites => _showFavorites;

  bool get isActive => _isActive;

  Color get headerTextColor => _headerTextColor;

  Color get headerBackgroundColor => _headerBackgroundColor;

  HeaderColors get currentHeaderColors => _currentHeaderColors;

  TimelineEntry get currentEra => _currentEra;

  TimelineEntry get nextEntry => _renderNextEntry;

  TimelineEntry get prevEntry => _renderPrevEntry;

  List<TimelineEntry> get entries => _entries;

  List<TimelineBackgroundColor> get backgroundColors => _backgroundColors;

  List<TickColors> get tickColors => _tickColors;

  List<TimelineAsset> get renderAssets => _renderAssets;

  /// 设置器，用于在时间线左侧切换装订线，以快速引用时间线上的收藏夹。
  set showFavorites(bool value) {
    if (_showFavorites != value) {
      _showFavorites = value;
      _startRendering();
    }
  }

  /// When a scale operation is detected, this setter is called:
  /// e.g. [_TimelineWidgetState.scaleStart()].
  set isInteracting(bool value) {
    if (value != _isInteracting) {
      _isInteracting = value;
      _updateSteady();
    }
  }

  /// Used to detect if the current scaling operation is still happening
  /// during the current frame in [advance()].
  set isScaling(bool value) {
    if (value != _isScaling) {
      _isScaling = value;
      _updateSteady();
    }
  }

  /// Toggle/stop rendering whenever the timeline is visible or hidden.
  set isActive(bool isIt) {
    if (isIt != _isActive) {
      _isActive = isIt;
      if (_isActive) {
        _startRendering();
      }
    }
  }

  /// Check that the viewport is steady - i.e. no taps, pans, scales or other gestures are being detected.
  void _updateSteady() {
    bool isIt = !_isInteracting && !_isScaling;

    /// If a timer is currently active, dispose it.
    if (_steadyTimer != null) {
      _steadyTimer.cancel();
      _steadyTimer = null;
    }

    if (isIt) {
      /// If another timer is still needed, recreate it.
      _steadyTimer = Timer(Duration(milliseconds: SteadyMilliseconds), () {
        _steadyTimer = null;
        _isSteady = true;
        _startRendering();
      });
    } else {
      /// Otherwise update the current state and schedule a new frame.
      _isSteady = false;
      _startRendering();
    }
  }

  /// Schedule a new frame.
  void _startRendering() {
    if (!_isFrameScheduled) {
      _isFrameScheduled = true;
      _lastFrameTime = 0.0;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
    }
  }

  /// Make sure that all the visible assets are being rendered and advanced
  /// according to the current state of the timeline.
  ///
  /// 确保已根据时间轴的当前状态渲染和推进所有可见资产。
  void beginFrame(Duration timeStamp) {
    _isFrameScheduled = false;

    final double t =
        timeStamp.inMicroseconds / Duration.microsecondsPerMillisecond / 1000.0;

    if (_lastFrameTime == 0.0) {
      _lastFrameTime = t;
      _isFrameScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
      return;
    }

    double elapsed = t - _lastFrameTime;

    print(
        'beginFrame: {t: ${t.toStringAsPrecision(4)}, lastFrameTime: ${_lastFrameTime.toStringAsPrecision(4)}, elapsed: ${elapsed.toStringAsPrecision(4)}');

    _lastFrameTime = t;

    if (!_advance(elapsed, true) && !_isFrameScheduled) {
      _isFrameScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
    }

    onNeedPaint?.call();
  }

  double screenPaddingInTime(double padding, double start, double end) {
    return padding / computeScale(start, end);
  }

  /// Compute the viewport scale from the start/end times.
  double computeScale(double start, double end) {
    return _height == 0.0 ? 1.0 : _height / (end - start);
  }

  /// 从本地包中加载所有资源。
  /// 此函数将从磁盘加载和解码 `timeline.json`，解码 JSON 文件，并填充所有 [TimelineEntry]。
  Future<List<TimelineEntry>> loadFromBundle(String filename) async {
    final data = await rootBundle.loadString(filename);
    final jsonEntries = json.decode(data) as List;

    final allEntries = <TimelineEntry>[];
    _backgroundColors = <TimelineBackgroundColor>[];
    _tickColors = <TickColors>[];
    _headerColors = <HeaderColors>[];

    /// JSON 解码不提供强类型，因此我们将迭代 [jsonEntries] 列表中的动态条目。
    for (dynamic entry in jsonEntries) {
      Map map = entry as Map;

      /// 完整性检查。
      if (map == null) continue;

      /// 如果是 “事件"，则创建当前条目并填写当前日期；如果是 "时代"，则查找 "start" 属性。
      /// 一些条目将具有一个 "开始" 元素，但没有指定一个 "结束" 元素。 这些条目指定了一个特定事件，
      /// 例如历史上 "人类" 的出现，但尚未结束。
      TimelineEntry timelineEntry = TimelineEntry();

      if (map.containsKey("date")) {
        timelineEntry.type = TimelineEntryType.Incident;
        dynamic date = map["date"];
        timelineEntry.start = date is int ? date.toDouble() : date;
      } else if (map.containsKey("start")) {
        timelineEntry.type = TimelineEntryType.Era;
        dynamic start = map["start"];
        timelineEntry.start = start is int ? start.toDouble() : start;
      } else {
        continue;
      }

      /// If a custom background color for this [TimelineEntry] is specified,
      /// extract its RGB values and save them for reference, along with the starting
      /// date of the current entry.
      if (map.containsKey("background")) {
        dynamic bg = map["background"];
        if (bg is List && bg.length >= 3) {
          _backgroundColors.add(TimelineBackgroundColor()
            ..color =
                Color.fromARGB(255, bg[0] as int, bg[1] as int, bg[2] as int)
            ..start = timelineEntry.start);
        }
      }

      /// An accent color is also specified at times.
      dynamic accent = map["accent"];
      if (accent is List && accent.length >= 3) {
        timelineEntry.accent = Color.fromARGB(
            accent.length > 3 ? accent[3] as int : 255,
            accent[0] as int,
            accent[1] as int,
            accent[2] as int);
      }

      /// [Ticks]也可以具有自定义颜色，因此即使使用自定义彩色背景，也可以看到所有内容。
      if (map.containsKey("ticks")) {
        dynamic ticks = map["ticks"];
        if (ticks is Map) {
          Color bgColor = Colors.black;
          Color longColor = Colors.black;
          Color shortColor = Colors.black;
          Color textColor = Colors.black;

          dynamic bg = ticks["background"];
          if (bg is List && bg.length >= 3) {
            bgColor = Color.fromARGB(bg.length > 3 ? bg[3] as int : 255,
                bg[0] as int, bg[1] as int, bg[2] as int);
          }
          dynamic long = ticks["long"];
          if (long is List && long.length >= 3) {
            longColor = Color.fromARGB(long.length > 3 ? long[3] as int : 255,
                long[0] as int, long[1] as int, long[2] as int);
          }
          dynamic short = ticks["short"];
          if (short is List && short.length >= 3) {
            shortColor = Color.fromARGB(
                short.length > 3 ? short[3] as int : 255,
                short[0] as int,
                short[1] as int,
                short[2] as int);
          }
          dynamic text = ticks["text"];
          if (text is List && text.length >= 3) {
            textColor = Color.fromARGB(text.length > 3 ? text[3] as int : 255,
                text[0] as int, text[1] as int, text[2] as int);
          }

          _tickColors.add(TickColors()
            ..background = bgColor
            ..long = longColor
            ..short = shortColor
            ..text = textColor
            ..start = timelineEntry.start
            ..screenY = 0.0);
        }
      }

      /// If a `header` element is present, de-serialize the colors for it too.
      if (map.containsKey("header")) {
        dynamic header = map["header"];
        if (header is Map) {
          Color bgColor = Colors.black;
          Color textColor = Colors.black;

          dynamic bg = header["background"];
          if (bg is List && bg.length >= 3) {
            bgColor = Color.fromARGB(bg.length > 3 ? bg[3] as int : 255,
                bg[0] as int, bg[1] as int, bg[2] as int);
          }
          dynamic text = header["text"];
          if (text is List && text.length >= 3) {
            textColor = Color.fromARGB(text.length > 3 ? text[3] as int : 255,
                text[0] as int, text[1] as int, text[2] as int);
          }

          _headerColors.add(HeaderColors()
            ..background = bgColor
            ..text = textColor
            ..start = timelineEntry.start
            ..screenY = 0.0);
        }
      }

      /// 有些元素将指定 “结束” 时间。 如果此条目中没有 `end` 键，则根据事件的类型创建值：
      /// -时代使用当前年份作为结束时间。
      /// -其他条目只是单个时间点（开始==结束）。
      if (map.containsKey("end")) {
        dynamic end = map["end"];
        timelineEntry.end = end is int ? end.toDouble() : end;
      } else if (timelineEntry.type == TimelineEntryType.Era) {
        timelineEntry.end = DateTime.now().year.toDouble() * 10.0;
      } else {
        timelineEntry.end = timelineEntry.start;
      }

      /// The label is a brief description for the current entry.
      if (map.containsKey("label")) {
        timelineEntry.label = map["label"] as String;
      }

      /// Some entries will also have an id
      if (map.containsKey("id")) {
        timelineEntry.id = map["id"] as String;
        _entriesById[timelineEntry.id] = timelineEntry;
      }
      if (map.containsKey("article")) {
        timelineEntry.articleFilename = map["article"] as String;
      }

      /// The `asset` key in the current entry contains all the information
      /// for the nima/flare animation file that'll be played on the timeline.
      ///
      /// `asset` is a JSON object thus made:
      /// {
      ///   - source: the name of the nima/flare file in the assets folder;
      ///   - width/height/offset/bounds/gap: sizes of the animation to properly align it in the timeline, together with its Axis-Aligned Bounding Box container.
      ///   - intro: some files have an 'intro' animation, to be played before idling.
      ///   - idle: some files have one or more idle animations, and these are their names.
      ///   - loop: some animations shouldn't loop (e.g. Big Bang) but just settle onto their idle animation. If that's the case, this flag is raised.
      ///   - scale: a custom scale value.
      /// }
      if (map.containsKey("asset")) {
        TimelineAsset asset;
        Map assetMap = map["asset"] as Map;
        String source = assetMap["source"];
        String filename = "assets/" + source;
        String extension = getExtension(source);

        /// Instantiate the correct object based on the file extension.
        switch (extension) {
          case "flr":
            TimelineFlare flareAsset = TimelineFlare();
            asset = flareAsset;
            flare.FlutterActor actor = _flareResources[filename];
            if (actor == null) {
              actor = flare.FlutterActor();

              /// Flare library function to load the [FlutterActor]
              bool success = await actor.loadFromBundle(rootBundle, filename);
              if (success) {
                /// Populate the Map.
                _flareResources[filename] = actor;
              }
            }
            if (actor != null) {
              /// Distinguish between the actual actor, and its intance.
              flareAsset.actorStatic = actor.artboard;
              flareAsset.actorStatic.initializeGraphics();
              flareAsset.actor = actor.artboard.makeInstance();
              flareAsset.actor.initializeGraphics();

              /// and the reference to their first animation is grabbed.
              flareAsset.animation = actor.artboard.animations[0];

              dynamic name = assetMap["idle"];
              if (name is String) {
                if ((flareAsset.idle = flareAsset.actor.getAnimation(name)) !=
                    null) {
                  flareAsset.animation = flareAsset.idle;
                }
              } else if (name is List) {
                for (String animationName in name) {
                  flare.ActorAnimation animation =
                      flareAsset.actor.getAnimation(animationName);
                  if (animation != null) {
                    if (flareAsset.idleAnimations == null) {
                      flareAsset.idleAnimations = List<flare.ActorAnimation>();
                    }
                    flareAsset.idleAnimations.add(animation);
                    flareAsset.animation = animation;
                  }
                }
              }

              name = assetMap["intro"];
              if (name is String) {
                if ((flareAsset.intro = flareAsset.actor.getAnimation(name)) !=
                    null) {
                  flareAsset.animation = flareAsset.intro;
                }
              }

              /// Make sure that all the initial values are set for the actor and for the actor instance.
              flareAsset.animationTime = 0.0;
              flareAsset.actor.advance(0.0);
              flareAsset.setupAABB = flareAsset.actor.computeAABB();
              flareAsset.animation
                  .apply(flareAsset.animationTime, flareAsset.actor, 1.0);
              flareAsset.animation.apply(
                  flareAsset.animation.duration, flareAsset.actorStatic, 1.0);
              flareAsset.actor.advance(0.0);
              flareAsset.actorStatic.advance(0.0);

              dynamic loop = assetMap["loop"];
              flareAsset.loop = loop is bool ? loop : true;
              dynamic offset = assetMap["offset"];
              flareAsset.offset = offset == null
                  ? 0.0
                  : offset is int
                      ? offset.toDouble()
                      : offset;
              dynamic gap = assetMap["gap"];
              flareAsset.gap = gap == null
                  ? 0.0
                  : gap is int
                      ? gap.toDouble()
                      : gap;

              dynamic bounds = assetMap["bounds"];
              if (bounds is List) {
                /// Override the AABB for this entry with custom values.
                flareAsset.setupAABB = flare.AABB.fromValues(
                    bounds[0] is int ? bounds[0].toDouble() : bounds[0],
                    bounds[1] is int ? bounds[1].toDouble() : bounds[1],
                    bounds[2] is int ? bounds[2].toDouble() : bounds[2],
                    bounds[3] is int ? bounds[3].toDouble() : bounds[3]);
              }
            }
            break;
          case "nma":
            TimelineNima nimaAsset = TimelineNima();
            asset = nimaAsset;
            nima.FlutterActor actor = _nimaResources[filename];
            if (actor == null) {
              actor = nima.FlutterActor();

              bool success = await actor.loadFromBundle(filename);
              if (success) {
                _nimaResources[filename] = actor;
              }
            }
            if (actor != null) {
              nimaAsset.actorStatic = actor;
              nimaAsset.actor = actor.makeInstance();

              dynamic name = assetMap["idle"];
              if (name is String) {
                nimaAsset.animation = nimaAsset.actor.getAnimation(name);
              } else {
                nimaAsset.animation = actor.animations[0];
              }
              nimaAsset.animationTime = 0.0;
              nimaAsset.actor.advance(0.0);

              nimaAsset.setupAABB = nimaAsset.actor.computeAABB();
              nimaAsset.animation
                  .apply(nimaAsset.animationTime, nimaAsset.actor, 1.0);
              nimaAsset.animation.apply(
                  nimaAsset.animation.duration, nimaAsset.actorStatic, 1.0);
              nimaAsset.actor.advance(0.0);
              nimaAsset.actorStatic.advance(0.0);
              dynamic loop = assetMap["loop"];
              nimaAsset.loop = loop is bool ? loop : true;
              dynamic offset = assetMap["offset"];
              nimaAsset.offset = offset == null
                  ? 0.0
                  : offset is int
                      ? offset.toDouble()
                      : offset;
              dynamic gap = assetMap["gap"];
              nimaAsset.gap = gap == null
                  ? 0.0
                  : gap is int
                      ? gap.toDouble()
                      : gap;
              dynamic bounds = assetMap["bounds"];
              if (bounds is List) {
                nimaAsset.setupAABB = nima.AABB.fromValues(
                    bounds[0] is int ? bounds[0].toDouble() : bounds[0],
                    bounds[1] is int ? bounds[1].toDouble() : bounds[1],
                    bounds[2] is int ? bounds[2].toDouble() : bounds[2],
                    bounds[3] is int ? bounds[3].toDouble() : bounds[3]);
              }
            }
            break;

          default:

            /// Legacy fallback case: some elements could have been just images.
            TimelineImage imageAsset = TimelineImage();
            asset = imageAsset;

            ByteData data = await rootBundle.load(filename);
            Uint8List list = Uint8List.view(data.buffer);
            ui.Codec codec = await ui.instantiateImageCodec(list);
            ui.FrameInfo frame = await codec.getNextFrame();
            imageAsset.image = frame.image;

            break;
        }

        double scale = 1.0;
        if (assetMap.containsKey("scale")) {
          dynamic s = assetMap["scale"];
          scale = s is int ? s.toDouble() : s;
        }

        dynamic width = assetMap["width"];
        asset.width = (width is int ? width.toDouble() : width) * scale;

        dynamic height = assetMap["height"];
        asset.height = (height is int ? height.toDouble() : height) * scale;

        asset.entry = timelineEntry;
        asset.filename = filename;
        timelineEntry.asset = asset;
      }

      /// Add this entry to the list.
      allEntries.add(timelineEntry);
    }

    /// 对完整列表进行排序，以使它们按照从旧到新的顺序排列
    allEntries.sort((TimelineEntry a, TimelineEntry b) {
      return a.start.compareTo(b.start);
    });

    /// DEBUG，标记 TimelineEntryType
    allEntries.forEach((element) {
      element.label =
          '<${element.type.toString().split('.')[1]}>\n${element.label}';
    });

    _backgroundColors
        .sort((TimelineBackgroundColor a, TimelineBackgroundColor b) {
      return a.start.compareTo(b.start);
    });

    _timeMin = double.maxFinite;
    _timeMax = -double.maxFinite;

    /// 列出“根”条目，即没有父母的条目。
    _entries = List<TimelineEntry>();

    /// 建立层次结构（将时代分为“跨越时代”，并将事件放入其所属的时代）。
    TimelineEntry previous; // 前一个 TimelineEntry
    // 遍历全部条目
    for (TimelineEntry entry in allEntries) {
      // 找出最早与最晚
      if (entry.start < _timeMin) _timeMin = entry.start;
      if (entry.end > _timeMax) _timeMax = entry.end;

      // 设置"前一个条目中的下一个条目"
      if (previous != null) {
        previous.next = entry;
      }
      // 设置上一个 TimelineEntry
      entry.previous = previous;

      // 更新 TimelineEntry
      previous = entry;

      // 父条目
      TimelineEntry parent;

      double minDistance = double.maxFinite;

      // 从远到近匹配 parent
      for (TimelineEntry checkEntry in allEntries) {
        // 检查条目是否为 TimelineEntryType.Era 即时代，只有时代有资格作为 Parent
        if (checkEntry.type != TimelineEntryType.Era) continue;

        // 计算事件开始与时代开始日期之间的距离
        double distance = entry.start - checkEntry.start;
        // TODO: ?
        double distanceEnd = entry.start - checkEntry.end;

        // distance > 0 保证事件在时代开始日期之后
        // distanceEnd < 0 TODO: ?...
        // distance < minDistance 保证当前匹配到的 parent 晚于上次匹配到的 parent
        if (distance > 0 && distanceEnd < 0 && distance < minDistance) {
          minDistance = distance;
          parent = checkEntry;
        }
      }

      if (parent != null) {
        entry.parent = parent;
        // 设置 父条目的孩子
        if (parent.children == null) {
          parent.children = <TimelineEntry>[];
        }
        parent.children.add(entry);
      } else {
        // 没有父母，所以这是一个根条目。
        _entries.add(entry);
      }
    }
    return allEntries;
  }

  /// Helper function for [MenuVignette].
  TimelineEntry getById(String id) {
    return _entriesById[id];
  }

  // /// 确保滚动时我们在正确的时间轴范围内。
  // clampScroll() {
  //   _scrollMetrics = null;
  //   _scrollPhysics = null;
  //   _scrollSimulation = null;
  //
  //   /// Get measurements values for the current viewport.
  //   double scale = computeScale(_start, _end);
  //   double padTop = (devicePadding.top + ViewportPaddingTop) / scale;
  //   double padBottom = (devicePadding.bottom + ViewportPaddingBottom) / scale;
  //   bool fixStart = _start < _timeMin - padTop;
  //   bool fixEnd = _end > _timeMax + padBottom;
  //
  //   /// As the scale changes we need to re-solve the right padding
  //   /// Don't think there's an analytical single solution for this
  //   /// so we do it in steps approaching the correct answer.
  //   for (int i = 0; i < 20; i++) {
  //     double scale = computeScale(_start, _end);
  //     double padTop = (devicePadding.top + ViewportPaddingTop) / scale;
  //     double padBottom = (devicePadding.bottom + ViewportPaddingBottom) / scale;
  //     if (fixStart) {
  //       _start = _timeMin - padTop;
  //     }
  //     if (fixEnd) {
  //       _end = _timeMax + padBottom;
  //     }
  //   }
  //   if (_end < _start) {
  //     _end = _start + _height / scale;
  //   }
  //
  //   /// Be sure to reschedule a new frame.
  //   if (!_isFrameScheduled) {
  //     _isFrameScheduled = true;
  //     _lastFrameTime = 0.0;
  //     SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
  //   }
  // }

  /// 1. App 启动时创建 [Timeline]
  ///   构造方法调用 [setViewport] 传入 [start] [end]，初始化 [_start] [_end] [_renderStart] [_renderEnd]，并推进时间轴到 0 位置。
  ///
  ///
  /// 此方法根据当前的开始和结束位置来限制当前视口。
  void setViewport({
    // 时间线起始位置
    double start = double.maxFinite,
    // 时间线结束位置
    double end = double.maxFinite,
    // 传入设备高度 (TimeLine Widget 高度)
    double height = double.maxFinite,
    // 是否设置 padding 值, 距离顶部的 padding 值
    bool pad = false,
    // 动画速度（滚动） ?
    double velocity = double.maxFinite,
    // 此操作是否使用动画
    bool animate = false,
  }) {
    print(
        'timeline#setViewport#{start: $start, end: $end, height: $height, pad: $pad, velocity: $velocity, animate: $animate}');

    /// 计算当前高度
    if (height != double.maxFinite) {
      // 检查 height 和 条目数量，不允许途中更改 _height
      if (_height == 0.0 && _entries != null && _entries.length > 0) {
        double scale = height / (_end - _start);
        _start = _start - padding.top / scale;
        _end = _end + padding.bottom / scale;
      }
      _height = height;
    }

    /// 如果提供了 start & end 的值，请相应地评估当前视口的 顶部/底部 位置。 否则，请分别构建值。
    if (start != double.maxFinite && end != double.maxFinite) {
      _start = start;
      _end = end;
      if (pad && _height != 0.0) {
        double scale = _height / (_end - _start);
        _start = _start - padding.top / scale;
        _end = _end + padding.bottom / scale;
      }
    } else {
      if (start != double.maxFinite) {
        double scale = height / (_end - _start);
        _start = pad ? start - padding.top / scale : start;
      }
      if (end != double.maxFinite) {
        double scale = height / (_end - _start);
        _end = pad ? end + padding.bottom / scale : end;
      }
    }

    /// 如果已经传递了速度值，请使用 [ScrollPhysics] 创建一个模拟并在本机上滚动到当前平台。
    if (velocity != double.maxFinite) {
      double scale = computeScale(_start, _end);
      double padTop =
          (devicePadding.top + ViewportPaddingTop) / computeScale(_start, _end);
      double padBottom = (devicePadding.bottom + ViewportPaddingBottom) /
          computeScale(_start, _end);
      double rangeMin = (_timeMin - padTop) * scale;
      double rangeMax = (_timeMax + padBottom) * scale - _height;
      if (rangeMax < rangeMin) {
        rangeMax = rangeMin;
      }

      _simulationTime = 0.0;
      if (_platform == TargetPlatform.iOS) {
        _scrollPhysics = BouncingScrollPhysics();
      } else {
        _scrollPhysics = ClampingScrollPhysics();
      }

      _scrollMetrics = FixedScrollMetrics(
          minScrollExtent: double.negativeInfinity,
          maxScrollExtent: double.infinity,
          pixels: 0.0,
          viewportDimension: _height,
          axisDirection: AxisDirection.down);

      _scrollSimulation =
          _scrollPhysics.createBallisticSimulation(_scrollMetrics, velocity);
    }

    if (!animate) {
      _renderStart = start;
      _renderEnd = end;
      _advance(0.0, false);
      onNeedPaint?.call();
    } else if (!_isFrameScheduled) {
      _isFrameScheduled = true;
      _lastFrameTime = 0.0;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
    }
  }

  /// See [beginFrame]
  bool _advance(double elapsed, bool animate) {
    if (_height <= 0) {
      /// 完成渲染，需要 _height
      return true;
    }

    /// 基于渲染区域的当前比例。
    double scale = _height / (_renderEnd - _renderStart);

    bool doneRendering = true;
    bool stillScaling = true;

    /// If the timeline is performing a scroll operation adjust the viewport
    /// based on the elapsed time.
    if (_scrollSimulation != null) {
      doneRendering = false;
      _simulationTime += elapsed;
      double scale = _height / (_end - _start);
      double velocity = _scrollSimulation.dx(_simulationTime);

      double displace = velocity * elapsed / scale;

      _start -= displace;
      _end -= displace;

      /// If scrolling has terminated, clean up the resources.
      if (_scrollSimulation.isDone(_simulationTime)) {
        _scrollMetrics = null;
        _scrollPhysics = null;
        _scrollSimulation = null;
      }
    }

    /// Check if the left-hand side gutter has been toggled.
    /// If visible, make room for it .
    double targetGutterWidth = _showFavorites ? GutterLeftExpanded : GutterLeft;
    double dgw = targetGutterWidth - _gutterWidth;
    if (!animate || dgw.abs() < 1) {
      _gutterWidth = targetGutterWidth;
    } else {
      doneRendering = false;
      _gutterWidth += dgw * min(1.0, elapsed * 10.0);
    }

    /// Animate movement.
    double speed =
        min(1.0, elapsed * (_isInteracting ? MoveSpeedInteracting : MoveSpeed));
    double ds = _start - _renderStart;
    double de = _end - _renderEnd;

    /// If the current view is animating, adjust the [_renderStart]/[_renderEnd] based on the interaction speed.
    if (!animate || ((ds * scale).abs() < 1.0 && (de * scale).abs() < 1.0)) {
      stillScaling = false;
      _renderStart = _start;
      _renderEnd = _end;
    } else {
      doneRendering = false;
      _renderStart += ds * speed;
      _renderEnd += de * speed;
    }
    isScaling = stillScaling;

    /// Update scale after changing render range.
    scale = _height / (_renderEnd - _renderStart);

    /// Update color screen positions.
    if (_tickColors != null && _tickColors.length > 0) {
      double lastStart = _tickColors.first.start;
      for (TickColors color in _tickColors) {
        color.screenY =
            (lastStart + (color.start - lastStart / 2.0) - _renderStart) *
                scale;
        lastStart = color.start;
      }
    }
    if (_headerColors != null && _headerColors.length > 0) {
      double lastStart = _headerColors.first.start;
      for (HeaderColors color in _headerColors) {
        color.screenY =
            (lastStart + (color.start - lastStart / 2.0) - _renderStart) *
                scale;
        lastStart = color.start;
      }
    }

    // _currentHeaderColors = _findHeaderColors(0.0);
    //
    // if (_currentHeaderColors != null) {
    //   if (_headerTextColor == null) {
    //     _headerTextColor = _currentHeaderColors.text;
    //     _headerBackgroundColor = _currentHeaderColors.background;
    //   } else {
    //     bool stillColoring = false;
    //     Color headerTextColor = interpolateColor(
    //         _headerTextColor, _currentHeaderColors.text, elapsed);
    //
    //     if (headerTextColor != _headerTextColor) {
    //       _headerTextColor = headerTextColor;
    //       stillColoring = true;
    //       doneRendering = false;
    //     }
    //     Color headerBackgroundColor = interpolateColor(
    //         _headerBackgroundColor, _currentHeaderColors.background, elapsed);
    //     if (headerBackgroundColor != _headerBackgroundColor) {
    //       _headerBackgroundColor = headerBackgroundColor;
    //       stillColoring = true;
    //       doneRendering = false;
    //     }
    //     if (stillColoring) {
    //       if (onHeaderColorsChanged != null) {
    //         onHeaderColorsChanged(_headerBackgroundColor, _headerTextColor);
    //       }
    //     }
    //   }
    // }

    /// Check all the visible entries and use the helper function [advanceItems()]
    /// to align their state with the elapsed time.
    /// Set all the initial values to defaults so that everything's consistent.
    _lastEntryY = -double.maxFinite;
    _lastOnScreenEntryY = 0.0;
    _firstOnScreenEntryY = double.maxFinite;
    _lastAssetY = -double.maxFinite;
    _labelX = 0.0;
    _offsetDepth = 0.0;
    _currentEra = null;
    _nextEntry = null;
    _prevEntry = null;
    if (_entries != null) {
      /// Advance the items hierarchy one level at a time.
      if (_advanceItems(
          _entries, _gutterWidth + LineSpacing, scale, elapsed, animate, 0)) {
        doneRendering = false;
      }

      /// Advance all the assets and add the rendered ones into [_renderAssets].
      _renderAssets = [];
      if (_advanceAssets(_entries, elapsed, animate, _renderAssets)) {
        doneRendering = false;
      }
    }

    if (_nextEntryOpacity == 0.0) {
      _renderNextEntry = _nextEntry;
    }

    /// Determine next entry's opacity and interpolate, if needed, towards that value.
    double targetNextEntryOpacity = _lastOnScreenEntryY > _height / 1.7 ||
            !_isSteady ||
            _distanceToNextEntry < 0.01 ||
            _nextEntry != _renderNextEntry
        ? 0.0
        : 1.0;
    double dt = targetNextEntryOpacity - _nextEntryOpacity;

    if (!animate || dt.abs() < 0.01) {
      _nextEntryOpacity = targetNextEntryOpacity;
    } else {
      doneRendering = false;
      _nextEntryOpacity += dt * min(1.0, elapsed * 10.0);
    }

    if (_prevEntryOpacity == 0.0) {
      _renderPrevEntry = _prevEntry;
    }

    /// Determine previous entry's opacity and interpolate, if needed, towards that value.
    double targetPrevEntryOpacity = _firstOnScreenEntryY < _height / 2.0 ||
            !_isSteady ||
            _distanceToPrevEntry < 0.01 ||
            _prevEntry != _renderPrevEntry
        ? 0.0
        : 1.0;
    dt = targetPrevEntryOpacity - _prevEntryOpacity;

    if (!animate || dt.abs() < 0.01) {
      _prevEntryOpacity = targetPrevEntryOpacity;
    } else {
      doneRendering = false;
      _prevEntryOpacity += dt * min(1.0, elapsed * 10.0);
    }

    /// Interpolate the horizontal position of the label.
    double dl = _labelX - _renderLabelX;
    if (!animate || dl.abs() < 1.0) {
      _renderLabelX = _labelX;
    } else {
      doneRendering = false;
      _renderLabelX += dl * min(1.0, elapsed * 6.0);
    }

    /// If a new era is currently in view, callback.
    if (_currentEra != _lastEra) {
      _lastEra = _currentEra;
      if (onEraChanged != null) {
        onEraChanged(_currentEra);
      }
    }

    if (_isSteady) {
      double dd = _offsetDepth - renderOffsetDepth;
      if (!animate || dd.abs() * DepthOffset < 1.0) {
        _renderOffsetDepth = _offsetDepth;
      } else {
        /// Needs a second run.
        doneRendering = false;
        _renderOffsetDepth += dd * min(1.0, elapsed * 12.0);
      }
    }

    return doneRendering;
  }

  TickColors findTickColors(double screen) {
    if (_tickColors == null) {
      return null;
    }
    for (TickColors color in _tickColors.reversed) {
      if (screen >= color.screenY) {
        return color;
      }
    }

    return screen < _tickColors.first.screenY
        ? _tickColors.first
        : _tickColors.last;
  }

  HeaderColors _findHeaderColors(double screen) {
    if (_headerColors == null) {
      return null;
    }
    for (HeaderColors color in _headerColors.reversed) {
      if (screen >= color.screenY) {
        return color;
      }
    }

    return screen < _headerColors.first.screenY
        ? _headerColors.first
        : _headerColors.last;
  }

  double bubbleHeight(TimelineEntry entry) {
    return BubblePadding * 2.0 + entry.lineCount * BubbleTextHeight;
  }

  /// Advance entry [assets] with the current [elapsed] time.
  bool _advanceItems(List<TimelineEntry> items, double x, double scale,
      double elapsed, bool animate, int depth) {
    bool stillAnimating = false;
    double lastEnd = -double.maxFinite;
    for (int i = 0; i < items.length; i++) {
      TimelineEntry item = items[i];

      double start = item.start - _renderStart;
      double end =
          item.type == TimelineEntryType.Era ? item.end - _renderStart : start;

      /// Vertical position for this element.
      double y = start * scale;

      ///+pad;
      if (i > 0 && y - lastEnd < EdgePadding) {
        y = lastEnd + EdgePadding;
      }

      /// Adjust based on current scale value.
      double endY = end * scale;

      ///-pad;
      /// Update the reference to the last found element.
      lastEnd = endY;

      item.length = endY - y;

      /// Calculate the best location for the bubble/label.
      double targetLabelY = y;
      double itemBubbleHeight = bubbleHeight(item);
      double fadeAnimationStart = itemBubbleHeight + BubblePadding / 2.0;
      if (targetLabelY - _lastEntryY < fadeAnimationStart

          /// The best location for our label is occluded, lets see if we can bump it forward...
          &&
          item.type == TimelineEntryType.Era &&
          _lastEntryY + fadeAnimationStart < endY) {
        targetLabelY = _lastEntryY + fadeAnimationStart + 0.5;
      }

      /// Determine if the label is in view.
      double targetLabelOpacity =
          targetLabelY - _lastEntryY < fadeAnimationStart ? 0.0 : 1.0;

      /// Debounce labels becoming visible.
      if (targetLabelOpacity > 0.0 && item.targetLabelOpacity != 1.0) {
        item.delayLabel = 0.5;
      }
      item.targetLabelOpacity = targetLabelOpacity;
      if (item.delayLabel > 0.0) {
        targetLabelOpacity = 0.0;
        item.delayLabel -= elapsed;
        stillAnimating = true;
      }

      double dt = targetLabelOpacity - item.labelOpacity;
      if (!animate || dt.abs() < 0.01) {
        item.labelOpacity = targetLabelOpacity;
      } else {
        stillAnimating = true;
        item.labelOpacity += dt * min(1.0, elapsed * 25.0);
      }

      /// Assign current vertical position.
      item.y = y;
      item.endY = endY;

      double targetLegOpacity = item.length > EdgeRadius ? 1.0 : 0.0;
      double dtl = targetLegOpacity - item.legOpacity;
      if (!animate || dtl.abs() < 0.01) {
        item.legOpacity = targetLegOpacity;
      } else {
        stillAnimating = true;
        item.legOpacity += dtl * min(1.0, elapsed * 20.0);
      }

      double targetItemOpacity = item.parent != null
          ? item.parent.length < MinChildLength ||
                  (item.parent != null && item.parent.endY < y)
              ? 0.0
              : y > item.parent.y
                  ? 1.0
                  : 0.0
          : 1.0;
      dtl = targetItemOpacity - item.opacity;
      if (!animate || dtl.abs() < 0.01) {
        item.opacity = targetItemOpacity;
      } else {
        stillAnimating = true;
        item.opacity += dtl * min(1.0, elapsed * 20.0);
      }

      /// Animate the label position.
      double targetLabelVelocity = targetLabelY - item.labelY;
      double dvy = targetLabelVelocity - item.labelVelocity;
      if (dvy.abs() > _height) {
        item.labelY = targetLabelY;
        item.labelVelocity = 0.0;
      } else {
        item.labelVelocity += dvy * elapsed * 18.0;
        item.labelY += item.labelVelocity * elapsed * 20.0;
      }

      /// Check the final position has been reached, otherwise raise a flag.
      if (animate &&
          (item.labelVelocity.abs() > 0.01 ||
              targetLabelVelocity.abs() > 0.01)) {
        stillAnimating = true;
      }

      if (item.targetLabelOpacity > 0.0) {
        _lastEntryY = targetLabelY;
        if (_lastEntryY < _height && _lastEntryY > devicePadding.top) {
          _lastOnScreenEntryY = _lastEntryY;
          if (_firstOnScreenEntryY == double.maxFinite) {
            _firstOnScreenEntryY = _lastEntryY;
          }
        }
      }

      if (item.type == TimelineEntryType.Era &&
          y < 0 &&
          endY > _height &&
          depth > _offsetDepth) {
        _offsetDepth = depth.toDouble();
      }

      /// A new era is currently in view.
      if (item.type == TimelineEntryType.Era && y < 0 && endY > _height / 2.0) {
        _currentEra = item;
      }

      /// Check if the bubble is out of view and set the y position to the
      /// target one directly.
      if (y > _height + itemBubbleHeight) {
        item.labelY = y;
        if (_nextEntry == null) {
          _nextEntry = item;
          _distanceToNextEntry = (y - _height) / _height;
        }
      } else if (endY < devicePadding.top) {
        _prevEntry = item;
        _distanceToPrevEntry = ((y - _height) / _height).abs();
      } else if (endY < -itemBubbleHeight) {
        item.labelY = y;
      }

      double lx = x + LineSpacing + LineSpacing;
      if (lx > _labelX) {
        _labelX = lx;
      }

      if (item.children != null && item.isVisible) {
        /// Advance the rest of the hierarchy.
        if (_advanceItems(item.children, x + LineSpacing + LineWidth, scale,
            elapsed, animate, depth + 1)) {
          stillAnimating = true;
        }
      }
    }
    return stillAnimating;
  }

  /// Advance asset [items] with the [elapsed] time.
  bool _advanceAssets(List<TimelineEntry> items, double elapsed, bool animate,
      List<TimelineAsset> renderAssets) {
    bool stillAnimating = false;
    for (TimelineEntry item in items) {
      /// Sanity check.
      if (item.asset != null) {
        double y = item.labelY;
        double halfHeight = _height / 2.0;
        double thresholdAssetY = y + ((y - halfHeight) / halfHeight) * Parallax;
        double targetAssetY =
            thresholdAssetY - item.asset.height * AssetScreenScale / 2.0;

        /// Determine if the current entry is visible or not.
        double targetAssetOpacity =
            (thresholdAssetY - _lastAssetY < 0 ? 0.0 : 1.0) *
                item.opacity *
                item.labelOpacity;

        /// Debounce asset becoming visible.
        if (targetAssetOpacity > 0.0 && item.targetAssetOpacity != 1.0) {
          item.delayAsset = 0.25;
        }
        item.targetAssetOpacity = targetAssetOpacity;
        if (item.delayAsset > 0.0) {
          /// If this item has been debounced, update it's debounce time.
          targetAssetOpacity = 0.0;
          item.delayAsset -= elapsed;
          stillAnimating = true;
        }

        /// Determine if the entry needs to be scaled.
        double targetScale = targetAssetOpacity;
        double targetScaleVelocity = targetScale - item.asset.scale;
        if (!animate || targetScale == 0) {
          item.asset.scaleVelocity = targetScaleVelocity;
        } else {
          double dvy = targetScaleVelocity - item.asset.scaleVelocity;
          item.asset.scaleVelocity += dvy * elapsed * 18.0;
        }

        item.asset.scale += item.asset.scaleVelocity * elapsed * 20.0;
        if (animate &&
            (item.asset.scaleVelocity.abs() > 0.01 ||
                targetScaleVelocity.abs() > 0.01)) {
          stillAnimating = true;
        }

        TimelineAsset asset = item.asset;
        if (asset.opacity == 0.0) {
          /// Item was invisible, just pop it to the right place and stop velocity.
          asset.y = targetAssetY;
          asset.velocity = 0.0;
        }

        /// Determinte the opacity delta and interpolate towards that value if needed.
        double da = targetAssetOpacity - asset.opacity;
        if (!animate || da.abs() < 0.01) {
          asset.opacity = targetAssetOpacity;
        } else {
          stillAnimating = true;
          asset.opacity += da * min(1.0, elapsed * 15.0);
        }

        /// This asset is visible.
        if (asset.opacity > 0.0) {
          /// Calculate the vertical delta, and assign the interpolated value.
          double targetAssetVelocity = max(_lastAssetY, targetAssetY) - asset.y;
          double dvay = targetAssetVelocity - asset.velocity;
          if (dvay.abs() > _height) {
            asset.y = targetAssetY;
            asset.velocity = 0.0;
          } else {
            asset.velocity += dvay * elapsed * 15.0;
            asset.y += asset.velocity * elapsed * 17.0;
          }

          /// Check if we reached our target and flag it if not.
          if (asset.velocity.abs() > 0.01 || targetAssetVelocity.abs() > 0.01) {
            stillAnimating = true;
          }

          _lastAssetY =
              targetAssetY + asset.height * AssetScreenScale + AssetPadding;
          if (asset is TimelineNima) {
            _lastAssetY += asset.gap;
          } else if (asset is TimelineFlare) {
            _lastAssetY += asset.gap;
          }
          if (asset.y > _height ||
              asset.y + asset.height * AssetScreenScale < 0.0) {
            /// It's not in view: cull it. Make sure we don't advance animations.
            if (asset is TimelineNima) {
              TimelineNima nimaAsset = asset;
              if (!nimaAsset.loop) {
                nimaAsset.animationTime = -1.0;
              }
            } else if (asset is TimelineFlare) {
              TimelineFlare flareAsset = asset;
              if (!flareAsset.loop) {
                flareAsset.animationTime = -1.0;
              } else if (flareAsset.intro != null) {
                flareAsset.animationTime = -1.0;
                flareAsset.animation = flareAsset.intro;
              }
            }
          } else {
            /// Item is in view, apply the new animation time and advance the actor.
            if (asset is TimelineNima && isActive) {
              asset.animationTime += elapsed;
              if (asset.loop) {
                asset.animationTime %= asset.animation.duration;
              }
              asset.animation.apply(asset.animationTime, asset.actor, 1.0);
              asset.actor.advance(elapsed);
              stillAnimating = true;
            } else if (asset is TimelineFlare && isActive) {
              asset.animationTime += elapsed;

              /// Flare animations can have idle animations, as well as intro animations.
              /// Distinguish which one has the top priority and apply it accordingly.
              if (asset.idleAnimations != null) {
                double phase = 0.0;
                for (flare.ActorAnimation animation in asset.idleAnimations) {
                  animation.apply(
                      (asset.animationTime + phase) % animation.duration,
                      asset.actor,
                      1.0);
                  phase += 0.16;
                }
              } else {
                if (asset.intro == asset.animation &&
                    asset.animationTime >= asset.animation.duration) {
                  asset.animationTime -= asset.animation.duration;
                  asset.animation = asset.idle;
                }
                if (asset.loop && asset.animationTime > 0) {
                  asset.animationTime %= asset.animation.duration;
                }
                asset.animation.apply(asset.animationTime, asset.actor, 1.0);
              }
              asset.actor.advance(elapsed);
              stillAnimating = true;
            }

            /// Add this asset to the list of rendered assets.
            renderAssets.add(item.asset);
          }
        } else {
          /// [item] is not visible.
          item.asset.y = max(_lastAssetY, targetAssetY);
        }
      }

      if (item.children != null && item.isVisible) {
        /// Proceed down the hierarchy.
        if (_advanceAssets(item.children, elapsed, animate, renderAssets)) {
          stillAnimating = true;
        }
      }
    }
    return stillAnimating;
  }
}
