import 'package:flutter/material.dart';

class SlideDrawerController extends ChangeNotifier {
  late final AnimationController _animationController;
  late final Animation<double> _animation;

  SlideDrawerController({required TickerProvider vsync}) {
    _animationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    _animationController.addListener(notifyListeners);
  }

  Animation<double> get animation => _animation;

  bool get isOpen => _animationController.value == 1.0;
  bool get isClosed => _animationController.value == 0.0;

  void open() => _animationController.forward();
  void close() => _animationController.reverse();
  void toggle() {
    if (isOpen) {
      close();
    } else {
      open();
    }
  }

  @override
  void dispose() {
    _animationController.removeListener(notifyListeners);
    _animationController.dispose();
    super.dispose();
  }
}

class SlideDrawer extends StatelessWidget {
  final SlideDrawerController controller;
  final Widget menuContent;
  final Widget mainContent;
  final double slideFraction;
  final double borderRadius;
  final double rotationAngle;

  const SlideDrawer({
    super.key,
    required this.controller,
    required this.menuContent,
    required this.mainContent,
    this.slideFraction = 0.65,
    this.borderRadius = 16.0,
    this.rotationAngle = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final screenWidth = MediaQuery.of(context).size.width;
        final slideWidth = screenWidth * slideFraction * controller.animation.value;
        final currentRadius = borderRadius * controller.animation.value;

        return Stack(
          children: [
            SizedBox(width: screenWidth, child: menuContent),
            GestureDetector(
              onTap: controller.isOpen ? controller.close : null,
              child: Transform.translate(
                offset: Offset(slideWidth, 0),
                child: Transform.rotate(
                  angle: rotationAngle * controller.animation.value,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(currentRadius),
                    child: Container(
                      width: screenWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        boxShadow: controller.animation.value > 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 20,
                                  offset: const Offset(-4, 0),
                                ),
                              ]
                            : null,
                      ),
                      child: mainContent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
