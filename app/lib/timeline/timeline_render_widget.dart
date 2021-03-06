import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

// ignore: unused_import
import 'package:flare_dart/actor_image.dart' as flare;
import 'package:flare_dart/math/aabb.dart' as flare;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ignore: unused_import
import 'package:nima/nima/actor_image.dart' as nima;
import 'package:nima/nima/math/aabb.dart' as nima;
import 'package:timeline/colors.dart';
import 'package:timeline/main.dart';
import 'package:timeline/main_menu/menu_data.dart';
import 'package:timeline/timeline/ticks.dart';
import 'package:timeline/timeline/timeline.dart';
import 'package:timeline/timeline/timeline_entry.dart';
import 'package:timeline/timeline/timeline_utils.dart';
import 'package:timeline/bloc_provider.dart';

/// These two callbacks are used to detect if a bubble or an entry have been tapped.
/// If that's the case, [ArticlePage] will be pushed onto the [Navigator] stack.
typedef TouchBubbleCallback(TapTarget bubble);
typedef TouchEntryCallback(TimelineEntry entry);

/// 这与[TimelineRenderObject]耦合。
///
/// 这个小部件的字段可以从[RenderBox]访问，因此它可以与当前状态对齐。
class TimelineRenderWidget extends LeafRenderObjectWidget {
  final double topOverlap;
  final Timeline timeline;
  final MenuItemData focusItem;
  final List<TimelineEntry> favorites;
  final TouchBubbleCallback touchBubble;
  final TouchEntryCallback touchEntry;

  TimelineRenderWidget({
    Key key,
    this.focusItem,
    this.touchBubble,
    this.touchEntry,
    this.topOverlap,
    this.timeline,
    this.favorites,
  }) : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return TimelineRenderObject()
      ..timeline = timeline
      ..touchBubble = touchBubble
      ..touchEntry = touchEntry
      ..focusItem = focusItem
      ..favorites = favorites
      ..topOverlap = topOverlap;
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant TimelineRenderObject renderObject) {
    renderObject
      ..timeline = timeline
      ..focusItem = focusItem
      ..touchBubble = touchBubble
      ..touchEntry = touchEntry
      ..favorites = favorites
      ..topOverlap = topOverlap;
  }

  @override
  void didUnmountRenderObject(covariant TimelineRenderObject renderObject) {
    renderObject.timeline.isActive = false;
  }
}

/// 自定义渲染器用于时间轴对象。
/// [Timeline] 用作定位和前进逻辑的抽象层。
/// 该对象的核心方法是 [paint]：这是所有元素实际绘制到屏幕上的位置。
class TimelineRenderObject extends RenderBox {
  static const List<Color> LineColors = [
    Color.fromARGB(255, 125, 195, 184),
    Color.fromARGB(255, 190, 224, 146),
    Color.fromARGB(255, 238, 155, 75),
    Color.fromARGB(255, 202, 79, 63),
    Color.fromARGB(255, 128, 28, 15)
  ];

  TouchBubbleCallback touchBubble;
  TouchEntryCallback touchEntry;

  final _ticks = Ticks();

  final _tapTargets = <TapTarget>[];

  MenuItemData _processedFocusItem;

  /// [Ticks] 距离设备顶部的高度，一般为 kToolbarHeight + MediaQuery.of(context).padding.top
  /// [kToolbarHeight]
  /// [MediaQueryData.padding]
  double _topOverlap = 0.0;
  Timeline _timeline;

  /// 喜爱的条目
  /// [BlocProvider.favorites]
  List<TimelineEntry> _favorites;
  MenuItemData _focusItem;

  //---------------------------------getter-------------------------------------

  double get topOverlap => _topOverlap;

  Timeline get timeline => _timeline;

  List<TimelineEntry> get favorites => _favorites;

  MenuItemData get focusItem => _focusItem;

  //---------------------------------setter-------------------------------------

  set topOverlap(double value) {
    if (_topOverlap == value) {
      return;
    }
    _topOverlap = value;
    updateFocusItem();
    markNeedsPaint();
    markNeedsLayout();
  }

  set timeline(Timeline value) {
    if (_timeline == value) {
      return;
    }
    _timeline = value;
    updateFocusItem();
    _timeline.onNeedPaint = markNeedsPaint;
    markNeedsPaint();
    markNeedsLayout();
  }

  set favorites(List<TimelineEntry> value) {
    if (_favorites == value) {
      return;
    }
    _favorites = value;
    markNeedsPaint();
    markNeedsLayout();
  }

  set focusItem(MenuItemData value) {
    if (_focusItem == value) {
      return;
    }
    _focusItem = value;
    _processedFocusItem = null;
    updateFocusItem();
  }

  //////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////

  @override
  bool get sizedByParent => true;

  /// 如果 [_focusItem] 已更新为新值，请更新当前视图。
  void updateFocusItem() {
    print('timeline_render_wiget#updateFocusItem');
    if (_processedFocusItem == _focusItem) {
      return;
    }

    if (_focusItem == null || timeline == null || topOverlap == 0.0) {
      return;
    }

    /// 调整当前的时间轴填充，从而调整视口。
    if (_focusItem.pad) {
      timeline.padding = EdgeInsets.only(
          top: topOverlap + _focusItem.padTop + Timeline.Parallax,
          bottom: _focusItem.padBottom);

      timeline.setViewport(start: _focusItem.start, end: _focusItem.end, animate: true, pad: true);
    } else {
      timeline.padding = EdgeInsets.zero;
      timeline.setViewport(start: _focusItem.start, end: _focusItem.end, animate: true);
    }
    _processedFocusItem = _focusItem;
  }

  /// 检查屏幕上当前的点击是否触碰到气泡。
  @override
  bool hitTestSelf(Offset screenOffset) {
    touchEntry(null);
    for (TapTarget bubble in _tapTargets.reversed) {
      if (bubble.rect.contains(screenOffset)) {
        if (touchBubble != null) {
          touchBubble(bubble);
        }
        return true;
      }
    }
    touchBubble(null);

    return true;
  }

  @override
  void performResize() {
    size = constraints.biggest;
  }

  /// Adjust the viewport when needed.
  /// 必要时调整视口。
  @override
  void performLayout() {
    if (_timeline != null) {
      print('------------setViewport by performLayout');
      print('------------height: ${size.height}');
      _timeline.setViewport(height: size.height, animate: true);
    }
  }

  final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
  final style = TextStyle(color: Colors.black, fontSize: 20);

  @override
  void paint(PaintingContext context, Offset offset) {
    // 获取画布
    final Canvas canvas = context.canvas;
    if (_timeline == null) {
      return;
    }

    final renderStart = _timeline.renderStart;
    final renderEnd = _timeline.renderEnd;

    // 从 [Timeline] 获取背景色并计算填充度。
    List<TimelineBackgroundColor> backgroundColors = timeline.backgroundColors;
    ui.Paint backgroundPaint;
    if (backgroundColors?.isNotEmpty ?? false) {
      // 找到第一个颜色的位置 [TimelineBackgroundColor.start]
      final rangeStart = backgroundColors.first.start;
      final rangeEnd = backgroundColors.last.start;

      // 背景色区域
      final range = rangeEnd - rangeStart;

      final colors = <ui.Color>[];
      final stops = <double>[];

      final s = timeline.computeScale(timeline.renderStart, timeline.renderEnd);

      final y1 = (rangeStart - renderStart) * s;
      final y2 = (rangeEnd - renderStart) * s;

      for (final bg in backgroundColors) {
        colors.add(bg.color);
        stops.add((bg.start - rangeStart) / range);
      }

      // print('timeline.renderStart: ${timeline.renderStart}');
      // print('timeline.renderEnd: ${timeline.renderEnd}');
      // print('s: ${s.toStringAsFixed(20)}');
      // print('y1: $y1');
      // print('y2: $y2');

      // print('rangeStart: $rangeStart');
      // print('rangeEnd: $rangeEnd');
      // print('range: $range');
      // print('colors: $colors');
      // print('stops: $stops');

      // 填充背景。
      backgroundPaint = ui.Paint()
        ..shader = ui.Gradient.linear(
            ui.Offset(0.0, y1), ui.Offset(0.0, y2), colors, stops)
        ..style = ui.PaintingStyle.fill;

      // 填充@1
      // 如果 y1 在屏幕内 (y1 > offset.dy), 填充 y1 到屏幕顶部(offset.dy)空间为
      // backgroundColors.first.color
      if (y1 > offset.dy) {
        canvas.drawRect(
            Rect.fromLTWH(
                offset.dx, offset.dy, size.width, y1 - offset.dy + 1.0),
            // before:
            // ui.Paint()..color = backgroundColors.first.color);
            // after:
            ui.Paint()..color = Colors.green);

        // TODO: DEBUG
        textPainter.text = TextSpan(
            text: 'y1 > offset.dy',
            style: TextStyle(color: Colors.white, fontSize: 20));
        textPainter.layout(); // 进行布局
        textPainter.paint(canvas, offset.translate(100, 100)); // 进行绘制
      }

      // 填充@2
      // 在画布上绘制背景。
      // 填充 y1 到 y2 之间的空间为 backgroundPaint (线性渐变)
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, y1, size.width, y2 - y1),
        backgroundPaint,
      );

      // TODO: DEBUG
      textPainter.text = TextSpan(
          text: 'offset.dy: ${offset.dy}\n'
              'y1: $y1',
          style: TextStyle(color: Colors.white, fontSize: 20));
      textPainter.layout(); // 进行布局
      textPainter.paint(canvas, Offset(300, y1)); // 进行绘制
    }

    _tapTargets.clear();

    final scale = size.height / (renderEnd - renderStart);

    // print('renderStart: $renderStart');
    // print('renderEnd: $renderEnd');
    // print(scale.toStringAsFixed(20));

    if (DRAW_IMAGE) {
      if (timeline.renderAssets != null) {
        canvas.save();
        canvas.clipRect(offset & size);
        for (TimelineAsset asset in timeline.renderAssets) {
          if (asset.opacity > 0) {
            double rs = 0.2 + asset.scale * 0.8;

            double w = asset.width * Timeline.AssetScreenScale;
            double h = asset.height * Timeline.AssetScreenScale;

            /// Draw the correct asset.
            if (asset is TimelineImage) {
              canvas.drawImageRect(
                  asset.image,
                  Rect.fromLTWH(0.0, 0.0, asset.width, asset.height),
                  Rect.fromLTWH(
                      offset.dx + size.width - w, asset.y, w * rs, h * rs),
                  Paint()
                    ..isAntiAlias = true
                    ..filterQuality = ui.FilterQuality.low
                    ..color = Colors.white.withOpacity(asset.opacity));
            } else if (asset is TimelineNima && asset.actor != null) {
              /// If we have a [TimelineNima] asset, set it up properly and paint it.
              ///
              /// 1. Calculate the bounds for the current object.
              /// An Axis-Aligned Bounding Box (AABB) is already set up when the asset is first loaded.
              /// We rely on this AABB to perform screen-space calculations.
              Alignment alignment = Alignment.center;
              BoxFit fit = BoxFit.cover;

              nima.AABB bounds = asset.setupAABB;

              double contentHeight = bounds[3] - bounds[1];
              double contentWidth = bounds[2] - bounds[0];
              double x = -bounds[0] -
                  contentWidth / 2.0 -
                  (alignment.x * contentWidth / 2.0) +
                  asset.offset;
              double y = -bounds[1] -
                  contentHeight / 2.0 +
                  (alignment.y * contentHeight / 2.0);

              Offset renderOffset = Offset(offset.dx + size.width - w, asset.y);
              Size renderSize = Size(w * rs, h * rs);

              double scaleX = 1.0, scaleY = 1.0;

              canvas.save();

              /// This widget is always set up to use [BoxFit.cover].
              /// But this behavior can be customized according to anyone's needs.
              /// The following switch/case contains all the various alternatives native to Flutter.
              switch (fit) {
                case BoxFit.fill:
                  scaleX = renderSize.width / contentWidth;
                  scaleY = renderSize.height / contentHeight;
                  break;
                case BoxFit.contain:
                  double minScale = min(renderSize.width / contentWidth,
                      renderSize.height / contentHeight);
                  scaleX = scaleY = minScale;
                  break;
                case BoxFit.cover:
                  double maxScale = max(renderSize.width / contentWidth,
                      renderSize.height / contentHeight);
                  scaleX = scaleY = maxScale;
                  break;
                case BoxFit.fitHeight:
                  double minScale = renderSize.height / contentHeight;
                  scaleX = scaleY = minScale;
                  break;
                case BoxFit.fitWidth:
                  double minScale = renderSize.width / contentWidth;
                  scaleX = scaleY = minScale;
                  break;
                case BoxFit.none:
                  scaleX = scaleY = 1.0;
                  break;
                case BoxFit.scaleDown:
                  double minScale = min(renderSize.width / contentWidth,
                      renderSize.height / contentHeight);
                  scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
                  break;
              }

              /// 2. Move the [canvas] to the right position so that the widget's position
              /// is center-aligned based on its offset, size and alignment position.
              canvas.translate(
                  renderOffset.dx +
                      renderSize.width / 2.0 +
                      (alignment.x * renderSize.width / 2.0),
                  renderOffset.dy +
                      renderSize.height / 2.0 +
                      (alignment.y * renderSize.height / 2.0));

              /// 3. Scale depending on the [fit].
              canvas.scale(scaleX, -scaleY);

              /// 4. Move the canvas to the correct [_nimaActor] position calculated above.
              canvas.translate(x, y);

              /// 5. perform the drawing operations.
              asset.actor.draw(canvas, asset.opacity);

              /// 6. Restore the canvas' original transform state.
              canvas.restore();

              /// 7. This asset is also a *tappable* element, add it to the list
              /// so it can be processed.
              _tapTargets.add(TapTarget()
                ..entry = asset.entry
                ..rect = renderOffset & renderSize);
            } else if (asset is TimelineFlare && asset.actor != null) {
              /// If we have a [TimelineFlare] asset set it up properly and paint it.
              ///
              /// 1. Calculate the bounds for the current object.
              /// An Axis-Aligned Bounding Box (AABB) is already set up when the asset is first loaded.
              /// We rely on this AABB to perform screen-space calculations.
              Alignment alignment = Alignment.center;
              BoxFit fit = BoxFit.cover;

              flare.AABB bounds = asset.setupAABB;
              double contentWidth = bounds[2] - bounds[0];
              double contentHeight = bounds[3] - bounds[1];
              double x = -bounds[0] -
                  contentWidth / 2.0 -
                  (alignment.x * contentWidth / 2.0) +
                  asset.offset;
              double y = -bounds[1] -
                  contentHeight / 2.0 +
                  (alignment.y * contentHeight / 2.0);

              Offset renderOffset = Offset(offset.dx + size.width - w, asset.y);
              Size renderSize = Size(w * rs, h * rs);

              double scaleX = 1.0, scaleY = 1.0;

              canvas.save();

              /// This widget is always set up to use [BoxFit.cover].
              /// But this behavior can be customized according to anyone's needs.
              /// The following switch/case contains all the various alternatives native to Flutter.
              switch (fit) {
                case BoxFit.fill:
                  scaleX = renderSize.width / contentWidth;
                  scaleY = renderSize.height / contentHeight;
                  break;
                case BoxFit.contain:
                  double minScale = min(renderSize.width / contentWidth,
                      renderSize.height / contentHeight);
                  scaleX = scaleY = minScale;
                  break;
                case BoxFit.cover:
                  double maxScale = max(renderSize.width / contentWidth,
                      renderSize.height / contentHeight);
                  scaleX = scaleY = maxScale;
                  break;
                case BoxFit.fitHeight:
                  double minScale = renderSize.height / contentHeight;
                  scaleX = scaleY = minScale;
                  break;
                case BoxFit.fitWidth:
                  double minScale = renderSize.width / contentWidth;
                  scaleX = scaleY = minScale;
                  break;
                case BoxFit.none:
                  scaleX = scaleY = 1.0;
                  break;
                case BoxFit.scaleDown:
                  double minScale = min(renderSize.width / contentWidth,
                      renderSize.height / contentHeight);
                  scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
                  break;
              }

              /// 2. Move the [canvas] to the right position so that the widget's position
              /// is center-aligned based on its offset, size and alignment position.
              canvas.translate(
                  renderOffset.dx +
                      renderSize.width / 2.0 +
                      (alignment.x * renderSize.width / 2.0),
                  renderOffset.dy +
                      renderSize.height / 2.0 +
                      (alignment.y * renderSize.height / 2.0));

              /// 3. Scale depending on the [fit].
              canvas.scale(scaleX, scaleY);

              /// 4. Move the canvas to the correct [_flareActor] position calculated above.
              canvas.translate(x, y);

              /// 5. perform the drawing operations.
              asset.actor.modulateOpacity = asset.opacity;
              asset.actor.draw(canvas);

              /// 6. Restore the canvas' original transform state.
              canvas.restore();

              /// 7. This asset is also a *tappable* element, add it to the list
              /// so it can be processed.
              _tapTargets.add(TapTarget()
                ..entry = asset.entry
                ..rect = renderOffset & renderSize);
            }
          }
        }
        canvas.restore();
      }
    }

    /// 在屏幕左侧绘制 [Ticks]。
    {
      canvas.save();

      /// 限制 Ticks 绘制于 AppBar 之下
      canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy + topOverlap,
          size.width, size.height - topOverlap));

      _ticks.paint(
          context, offset, -renderStart * scale, scale, size.height, timeline);

      canvas.restore();
    }

    /// 然后绘制时间轴的其余部分。
    if (_timeline.entries != null) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(offset.dx + _timeline.gutterWidth,
          offset.dy, size.width - _timeline.gutterWidth, size.height));
      drawItems(
          context,
          offset,
          _timeline.entries,
          _timeline.gutterWidth +
              Timeline.LineSpacing -
              Timeline.DepthOffset * _timeline.renderOffsetDepth,
          scale,
          0);
      canvas.restore();
    }

    /// 在时间轴上不活动了片刻之后，如果有足够的空间，则指向时间轴上下一个事件的箭头将出现在屏幕底部。
    /// 绘制它，并将其添加为另一个[TapTarget]。
    if (_timeline.nextEntry != null && _timeline.nextEntryOpacity > 0.0) {
      double x = offset.dx + _timeline.gutterWidth - Timeline.GutterLeft;
      double opacity = _timeline.nextEntryOpacity;
      Color color = Color.fromRGBO(69, 211, 197, opacity);
      double pageSize = (_timeline.renderEnd - _timeline.renderStart);
      double pageReference = _timeline.renderEnd;

      /// Use a Paragraph to draw the arrow's label and page scrolls on canvas:
      /// 1. Create a [ParagraphBuilder] that'll be initialized with the correct styling information;
      /// 2. Add some text to the builder;
      /// 3. Build the [Paragraph];
      /// 4. Lay out the text with custom [ParagraphConstraints].
      /// 5. Draw the Paragraph at the right offset.
      const double MaxLabelWidth = 1200.0;
      ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.start, fontFamily: "Roboto", fontSize: 20.0))
        ..pushStyle(ui.TextStyle(color: color));

      builder.addText(_timeline.nextEntry.label);
      ui.Paragraph labelParagraph = builder.build();
      labelParagraph.layout(ui.ParagraphConstraints(width: MaxLabelWidth));

      double y = offset.dy + size.height - 200.0;
      double labelX =
          x + size.width / 2.0 - labelParagraph.maxIntrinsicWidth / 2.0;
      canvas.drawParagraph(labelParagraph, Offset(labelX, y));
      y += labelParagraph.height;

      /// Calculate the boundaries of the arrow icon.
      Rect nextEntryRect = Rect.fromLTWH(labelX, y,
          labelParagraph.maxIntrinsicWidth, offset.dy + size.height - y);

      const double radius = 25.0;
      labelX = x + size.width / 2.0;
      y += 15 + radius;

      /// Draw the background circle.
      canvas.drawCircle(
          Offset(labelX, y),
          radius,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill);
      nextEntryRect.expandToInclude(Rect.fromLTWH(
          labelX - radius, y - radius, radius * 2.0, radius * 2.0));
      Path path = Path();
      double arrowSize = 6.0;
      double arrowOffset = 1.0;

      /// Draw the stylized arrow on top of the circle.
      path.moveTo(x + size.width / 2.0 - arrowSize,
          y - arrowSize + arrowSize / 2.0 + arrowOffset);
      path.lineTo(x + size.width / 2.0, y + arrowSize / 2.0 + arrowOffset);
      path.lineTo(x + size.width / 2.0 + arrowSize,
          y - arrowSize + arrowSize / 2.0 + arrowOffset);
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity(opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0);
      y += 15 + radius;

      builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontFamily: "Roboto",
          fontSize: 14.0,
          height: 1.3))
        ..pushStyle(ui.TextStyle(color: color));

      double timeUntil = _timeline.nextEntry.start - pageReference;
      double pages = timeUntil / pageSize;
      NumberFormat formatter = NumberFormat.compact();
      String pagesFormatted = formatter.format(pages);
      String until = "in " +
          TimelineEntry.formatYears(timeUntil).toLowerCase() +
          "\n($pagesFormatted page scrolls)";
      builder.addText(until);
      labelParagraph = builder.build();
      labelParagraph.layout(ui.ParagraphConstraints(width: size.width));

      /// Draw the Paragraph beneath the circle.
      canvas.drawParagraph(labelParagraph, Offset(x, y));
      y += labelParagraph.height;

      /// Add this to the list of *tappable* elements.
      _tapTargets.add(TapTarget()
        ..entry = _timeline.nextEntry
        ..rect = nextEntryRect
        ..zoom = true);
    }

    /// Repeat the same procedure as above for the arrow pointing to the previous event on the timeline.
    if (_timeline.prevEntry != null && _timeline.prevEntryOpacity > 0.0) {
      double x = offset.dx + _timeline.gutterWidth - Timeline.GutterLeft;
      double opacity = _timeline.prevEntryOpacity;
      Color color = Color.fromRGBO(69, 211, 197, opacity);
      double pageSize = (_timeline.renderEnd - _timeline.renderStart);
      double pageReference = _timeline.renderEnd;

      const double MaxLabelWidth = 1200.0;
      ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.start, fontFamily: "Roboto", fontSize: 20.0))
        ..pushStyle(ui.TextStyle(color: color));

      builder.addText(_timeline.prevEntry.label);
      ui.Paragraph labelParagraph = builder.build();
      labelParagraph.layout(ui.ParagraphConstraints(width: MaxLabelWidth));

      double y = offset.dy + topOverlap + 20.0;
      double labelX =
          x + size.width / 2.0 - labelParagraph.maxIntrinsicWidth / 2.0;
      canvas.drawParagraph(labelParagraph, Offset(labelX, y));
      y += labelParagraph.height;

      Rect prevEntryRect = Rect.fromLTWH(labelX, y,
          labelParagraph.maxIntrinsicWidth, offset.dy + size.height - y);

      const double radius = 25.0;
      labelX = x + size.width / 2.0;
      y += 15 + radius;
      canvas.drawCircle(
          Offset(labelX, y),
          radius,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill);
      prevEntryRect.expandToInclude(Rect.fromLTWH(
          labelX - radius, y - radius, radius * 2.0, radius * 2.0));
      Path path = Path();
      double arrowSize = 6.0;
      double arrowOffset = 1.0;
      path.moveTo(
          x + size.width / 2.0 - arrowSize, y + arrowSize / 2.0 + arrowOffset);
      path.lineTo(x + size.width / 2.0, y - arrowSize / 2.0 + arrowOffset);
      path.lineTo(
          x + size.width / 2.0 + arrowSize, y + arrowSize / 2.0 + arrowOffset);
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity(opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0);
      y += 15 + radius;

      builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontFamily: "Roboto",
          fontSize: 14.0,
          height: 1.3))
        ..pushStyle(ui.TextStyle(color: color));

      double timeUntil = _timeline.prevEntry.start - pageReference;
      double pages = timeUntil / pageSize;
      NumberFormat formatter = NumberFormat.compact();
      String pagesFormatted = formatter.format(pages.abs());
      String until = TimelineEntry.formatYears(timeUntil).toLowerCase() +
          " ago\n($pagesFormatted page scrolls)";
      builder.addText(until);
      labelParagraph = builder.build();
      labelParagraph.layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(labelParagraph, Offset(x, y));
      y += labelParagraph.height;

      _tapTargets.add(TapTarget()
        ..entry = _timeline.prevEntry
        ..rect = prevEntryRect
        ..zoom = true);
    }

    /// When the user presses the heart button on the top right corner of the timeline
    /// a gutter on the left side shows up so that favorite elements are quickly accessible.
    ///
    /// Here the gutter gets drawn, and the elements are added as *tappable* targets.
    double favoritesGutter = _timeline.gutterWidth - Timeline.GutterLeft;
    if (_favorites != null && _favorites.length > 0 && favoritesGutter > 0.0) {
      Paint accentPaint = Paint()
        ..color = favoritesGutterAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      Paint accentFill = Paint()
        ..color = favoritesGutterAccent
        ..style = PaintingStyle.fill;
      Paint whitePaint = Paint()..color = Colors.white;
      double scale =
          timeline.computeScale(timeline.renderStart, timeline.renderEnd);
      double fullMargin = 50.0;
      double favoritesRadius = 20.0;
      double fullMarginOffset = fullMargin + favoritesRadius + 11.0;
      double x = offset.dx -
          fullMargin +
          favoritesGutter /
              (Timeline.GutterLeftExpanded - Timeline.GutterLeft) *
              fullMarginOffset;

      double padFavorites = 20.0;

      /// Order favorites by distance from mid.
      List<TimelineEntry> nearbyFavorites =
          List<TimelineEntry>.from(_favorites);
      double mid = timeline.renderStart +
          (timeline.renderEnd - timeline.renderStart) / 2.0;
      nearbyFavorites.sort((TimelineEntry a, TimelineEntry b) {
        return (a.start - mid).abs().compareTo((b.start - mid).abs());
      });

      /// layout favorites.
      for (int i = 0; i < nearbyFavorites.length; i++) {
        TimelineEntry favorite = nearbyFavorites[i];
        double y = ((favorite.start - timeline.renderStart) * scale).clamp(
            offset.dy + topOverlap + favoritesRadius + padFavorites,
            offset.dy + size.height - favoritesRadius - padFavorites);
        favorite.favoriteY = y;

        /// Check all closer events to see if this one is occluded by a previous closer one.
        /// Works because we sorted by distance.
        favorite.isFavoriteOccluded = false;
        for (int j = 0; j < i; j++) {
          TimelineEntry closer = nearbyFavorites[j];
          if ((favorite.favoriteY - closer.favoriteY).abs() <= 1.0) {
            favorite.isFavoriteOccluded = true;
            break;
          }
        }
      }

      /// Iterate the list from the bottom.
      for (TimelineEntry favorite in nearbyFavorites.reversed) {
        if (favorite.isFavoriteOccluded) {
          continue;
        }
        double y = favorite.favoriteY;

        /// Draw the favorite circle in the gutter for this item.
        canvas.drawCircle(
            Offset(x, y),
            favoritesRadius,
            backgroundPaint != null ? backgroundPaint : Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill);
        canvas.drawCircle(Offset(x, y), favoritesRadius, accentPaint);
        canvas.drawCircle(Offset(x, y), favoritesRadius - 4.0, whitePaint);

        TimelineAsset asset = favorite.asset;
        double assetSize = 40.0 - 8.0;
        Size renderSize = Size(assetSize, assetSize);
        Offset renderOffset = Offset(x - assetSize / 2.0, y - assetSize / 2.0);

        Alignment alignment = Alignment.center;
        BoxFit fit = BoxFit.cover;

        /// Draw the assets statically within the circle.
        /// Calculations here are the same as seen in [paint()] for the assets.
        if (asset is TimelineNima && asset.actorStatic != null) {
          nima.AABB bounds = asset.setupAABB;

          double contentHeight = bounds[3] - bounds[1];
          double contentWidth = bounds[2] - bounds[0];
          double x = -bounds[0] -
              contentWidth / 2.0 -
              (alignment.x * contentWidth / 2.0) +
              asset.offset;
          double y = -bounds[1] -
              contentHeight / 2.0 +
              (alignment.y * contentHeight / 2.0);

          double scaleX = 1.0, scaleY = 1.0;

          canvas.save();
          canvas.clipRRect(RRect.fromRectAndRadius(
              renderOffset & renderSize, Radius.circular(favoritesRadius)));

          switch (fit) {
            case BoxFit.fill:
              scaleX = renderSize.width / contentWidth;
              scaleY = renderSize.height / contentHeight;
              break;
            case BoxFit.contain:
              double minScale = min(renderSize.width / contentWidth,
                  renderSize.height / contentHeight);
              scaleX = scaleY = minScale;
              break;
            case BoxFit.cover:
              double maxScale = max(renderSize.width / contentWidth,
                  renderSize.height / contentHeight);
              scaleX = scaleY = maxScale;
              break;
            case BoxFit.fitHeight:
              double minScale = renderSize.height / contentHeight;
              scaleX = scaleY = minScale;
              break;
            case BoxFit.fitWidth:
              double minScale = renderSize.width / contentWidth;
              scaleX = scaleY = minScale;
              break;
            case BoxFit.none:
              scaleX = scaleY = 1.0;
              break;
            case BoxFit.scaleDown:
              double minScale = min(renderSize.width / contentWidth,
                  renderSize.height / contentHeight);
              scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
              break;
          }

          canvas.translate(
              renderOffset.dx +
                  renderSize.width / 2.0 +
                  (alignment.x * renderSize.width / 2.0),
              renderOffset.dy +
                  renderSize.height / 2.0 +
                  (alignment.y * renderSize.height / 2.0));
          canvas.scale(scaleX, -scaleY);
          canvas.translate(x, y);

          asset.actorStatic.draw(canvas);
          canvas.restore();
          _tapTargets.add(TapTarget()
            ..entry = asset.entry
            ..rect = renderOffset & renderSize
            ..zoom = true);
        } else if (asset is TimelineFlare && asset.actorStatic != null) {
          flare.AABB bounds = asset.setupAABB;
          double contentWidth = bounds[2] - bounds[0];
          double contentHeight = bounds[3] - bounds[1];
          double x = -bounds[0] -
              contentWidth / 2.0 -
              (alignment.x * contentWidth / 2.0) +
              asset.offset;
          double y = -bounds[1] -
              contentHeight / 2.0 +
              (alignment.y * contentHeight / 2.0);

          double scaleX = 1.0, scaleY = 1.0;

          canvas.save();
          canvas.clipRRect(RRect.fromRectAndRadius(
              renderOffset & renderSize, Radius.circular(favoritesRadius)));

          switch (fit) {
            case BoxFit.fill:
              scaleX = renderSize.width / contentWidth;
              scaleY = renderSize.height / contentHeight;
              break;
            case BoxFit.contain:
              double minScale = min(renderSize.width / contentWidth,
                  renderSize.height / contentHeight);
              scaleX = scaleY = minScale;
              break;
            case BoxFit.cover:
              double maxScale = max(renderSize.width / contentWidth,
                  renderSize.height / contentHeight);
              scaleX = scaleY = maxScale;
              break;
            case BoxFit.fitHeight:
              double minScale = renderSize.height / contentHeight;
              scaleX = scaleY = minScale;
              break;
            case BoxFit.fitWidth:
              double minScale = renderSize.width / contentWidth;
              scaleX = scaleY = minScale;
              break;
            case BoxFit.none:
              scaleX = scaleY = 1.0;
              break;
            case BoxFit.scaleDown:
              double minScale = min(renderSize.width / contentWidth,
                  renderSize.height / contentHeight);
              scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
              break;
          }

          canvas.translate(
              renderOffset.dx +
                  renderSize.width / 2.0 +
                  (alignment.x * renderSize.width / 2.0),
              renderOffset.dy +
                  renderSize.height / 2.0 +
                  (alignment.y * renderSize.height / 2.0));
          canvas.scale(scaleX, scaleY);
          canvas.translate(x, y);

          asset.actorStatic.draw(canvas);
          canvas.restore();
          _tapTargets.add(TapTarget()
            ..entry = asset.entry
            ..rect = renderOffset & renderSize
            ..zoom = true);
        } else {
          _tapTargets.add(TapTarget()
            ..entry = favorite
            ..rect = renderOffset & renderSize
            ..zoom = true);
        }
      }

      /// If there are two or more favorites in the gutter, show a line connecting
      /// the two circles, with the time between those two favorites as a label within a bubble.
      ///
      /// Uses same [ui.ParagraphBuilder] logic as seen above.
      TimelineEntry previous;
      for (TimelineEntry favorite in _favorites) {
        if (favorite.isFavoriteOccluded) {
          continue;
        }
        if (previous != null) {
          double distance = (favorite.favoriteY - previous.favoriteY);
          if (distance > favoritesRadius * 2.0) {
            canvas.drawLine(Offset(x, previous.favoriteY + favoritesRadius),
                Offset(x, favorite.favoriteY - favoritesRadius), accentPaint);
            double labelY = previous.favoriteY + distance / 2.0;
            double labelWidth = 37.0;
            double labelHeight = 8.5 * 2.0;
            if (distance - favoritesRadius * 2.0 > labelHeight) {
              ui.ParagraphBuilder builder = ui.ParagraphBuilder(
                  ui.ParagraphStyle(
                      textAlign: TextAlign.center,
                      fontFamily: "RobotoMedium",
                      fontSize: 10.0))
                ..pushStyle(ui.TextStyle(color: Colors.white));

              int value = (favorite.start - previous.start).round().abs();
              String label;
              if (value < 9000) {
                label = value.toStringAsFixed(0);
              } else {
                NumberFormat formatter = NumberFormat.compact();
                label = formatter.format(value);
              }

              builder.addText(label);
              ui.Paragraph distanceParagraph = builder.build();
              distanceParagraph
                  .layout(ui.ParagraphConstraints(width: labelWidth));

              canvas.drawRRect(
                  RRect.fromRectAndRadius(
                      Rect.fromLTWH(x - labelWidth / 2.0,
                          labelY - labelHeight / 2.0, labelWidth, labelHeight),
                      Radius.circular(labelHeight)),
                  accentFill);
              canvas.drawParagraph(
                  distanceParagraph,
                  Offset(x - labelWidth / 2.0,
                      labelY - distanceParagraph.height / 2.0));
            }
          }
        }
        previous = favorite;
      }
    }
  }

  /// Given a list of [entries], draw the label with its bubble beneath.
  /// Draw also the dots&lines on the left side of the timeline. These represent
  /// the starting/ending points for a given event and are meant to give the idea of
  /// the timespan encompassing that event, as well as putting the vent into context
  /// relative to the other events.
  void drawItems(PaintingContext context, Offset offset,
      List<TimelineEntry> entries, double x, double scale, int depth) {
    final Canvas canvas = context.canvas;

    for (TimelineEntry item in entries) {
      if (!item.isVisible ||
          item.y > size.height + Timeline.BubbleHeight ||
          item.endY < -Timeline.BubbleHeight) {
        /// Don't paint this item.
        continue;
      }

      double legOpacity = item.legOpacity * item.opacity;
      Offset entryOffset = Offset(x + Timeline.LineWidth / 2.0, item.y);

      /// Draw the small circle on the left side of the timeline.
      canvas.drawCircle(
          entryOffset,
          Timeline.EdgeRadius,
          Paint()
            ..color = (item.accent != null
                    ? item.accent
                    : LineColors[depth % LineColors.length])
                .withOpacity(item.opacity));
      if (legOpacity > 0.0) {
        Paint legPaint = Paint()
          ..color = (item.accent != null
                  ? item.accent
                  : LineColors[depth % LineColors.length])
              .withOpacity(legOpacity);

        /// Draw the line connecting the start&point of this item on the timeline.
        canvas.drawRect(
            Offset(x, item.y) & Size(Timeline.LineWidth, item.length),
            legPaint);
        canvas.drawCircle(
            Offset(x + Timeline.LineWidth / 2.0, item.y + item.length),
            Timeline.EdgeRadius,
            legPaint);
      }

      const double MaxLabelWidth = 1200.0;
      const double BubblePadding = 20.0;

      /// Let the timeline calculate the height for the current item's bubble.
      double bubbleHeight = timeline.bubbleHeight(item);

      /// Use [ui.ParagraphBuilder] to construct the label for canvas.
      ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.start, fontFamily: "Roboto", fontSize: 20.0))
        ..pushStyle(
            ui.TextStyle(color: const Color.fromRGBO(255, 255, 255, 1.0)));

      builder.addText(item.label);
      ui.Paragraph labelParagraph = builder.build();
      labelParagraph.layout(ui.ParagraphConstraints(width: MaxLabelWidth));

      double textWidth =
          labelParagraph.maxIntrinsicWidth * item.opacity * item.labelOpacity;
      double bubbleX = _timeline.renderLabelX -
          Timeline.DepthOffset * _timeline.renderOffsetDepth;
      double bubbleY = item.labelY - bubbleHeight / 2.0;

      canvas.save();
      canvas.translate(bubbleX, bubbleY);

      /// Get the bubble's path based on its width&height, draw it, and then add the label on top.
      Path bubble =
          makeBubblePath(textWidth + BubblePadding * 2.0, bubbleHeight);

      canvas.drawPath(
          bubble,
          Paint()
            ..color = (item.accent != null
                    ? item.accent
                    : LineColors[depth % LineColors.length])
                .withOpacity(item.opacity * item.labelOpacity));
      canvas
          .clipRect(Rect.fromLTWH(BubblePadding, 0.0, textWidth, bubbleHeight));
      _tapTargets.add(TapTarget()
        ..entry = item
        ..rect = Rect.fromLTWH(
            bubbleX, bubbleY, textWidth + BubblePadding * 2.0, bubbleHeight));

      canvas.drawParagraph(
          labelParagraph,
          Offset(
              BubblePadding, bubbleHeight / 2.0 - labelParagraph.height / 2.0));
      canvas.restore();
      if (item.children != null) {
        /// Draw the other elements in the hierarchy.
        drawItems(context, offset, item.children, x + Timeline.DepthOffset,
            scale, depth + 1);
      }
    }
  }

  /// Given a width and a height, design a path for the bubble that lies behind events' labels
  /// on the timeline, and return it.
  Path makeBubblePath(double width, double height) {
    const double ArrowSize = 19.0;
    const double CornerRadius = 10.0;

    const double circularConstant = 0.55;
    const double icircularConstant = 1.0 - circularConstant;

    Path path = Path();

    path.moveTo(CornerRadius, 0.0);
    path.lineTo(width - CornerRadius, 0.0);
    path.cubicTo(width - CornerRadius + CornerRadius * circularConstant, 0.0,
        width, CornerRadius * icircularConstant, width, CornerRadius);
    path.lineTo(width, height - CornerRadius);
    path.cubicTo(
        width,
        height - CornerRadius + CornerRadius * circularConstant,
        width - CornerRadius * icircularConstant,
        height,
        width - CornerRadius,
        height);
    path.lineTo(CornerRadius, height);
    path.cubicTo(CornerRadius * icircularConstant, height, 0.0,
        height - CornerRadius * icircularConstant, 0.0, height - CornerRadius);

    path.lineTo(0.0, height / 2.0 + ArrowSize / 2.0);
    path.lineTo(-ArrowSize / 2.0, height / 2.0);
    path.lineTo(0.0, height / 2.0 - ArrowSize / 2.0);

    path.lineTo(0.0, CornerRadius);

    path.cubicTo(0.0, CornerRadius * icircularConstant,
        CornerRadius * icircularConstant, 0.0, CornerRadius, 0.0);

    path.close();

    return path;
  }
}
