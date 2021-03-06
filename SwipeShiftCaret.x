#import <UIKit/UIKit.h>

%config(generator=internal);

#define PREF_PATH @"/var/mobile/Library/Preferences/jp.r-plus.SwipeShiftCaret.plist"

static UIView *tv;
static BOOL panGestureEnabled;

@interface UIView (Private) <UITextInput>
@end

@interface UIKeyboardImpl : NSObject
+ (id)sharedInstance;
- (BOOL)callLayoutIsShiftKeyBeingHeld;
@end

@interface SCSwipeGestureRecognizer : UISwipeGestureRecognizer
@end

@implementation SCSwipeGestureRecognizer
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)gesture {
  if ([gesture isMemberOfClass:[SCSwipeGestureRecognizer class]])
    return YES;
  return NO;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)gesture {
  if ([gesture isKindOfClass:[UISwipeGestureRecognizer class]] &&
      // Don't prevent SwipeNav
      ![gesture isMemberOfClass:%c(SNSwipeGestureRecognizer)])
    return YES;
  return NO;
}
@end

@interface SCPanGestureRecognizer : UIPanGestureRecognizer
@end

@implementation SCPanGestureRecognizer
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)gesture {
  if ([gesture isMemberOfClass:[SCPanGestureRecognizer class]])
    return YES;
  return NO;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)gesture {
  if (([gesture isMemberOfClass:[SCPanGestureRecognizer class]] ||
      [gesture isKindOfClass:[UISwipeGestureRecognizer class]]) &&
      // Don't prevent SwipeNav
      ![gesture isMemberOfClass:%c(SNSwipeGestureRecognizer)])
    return YES;
  return NO;
}
@end

static void InstallSwipeGestureRecognizer()
{
  if ([tv isKindOfClass:[UIView class]]) {
    SCSwipeGestureRecognizer *rightSwipeShiftCaret = [[SCSwipeGestureRecognizer alloc] initWithTarget:tv action:@selector(rightSwipeShiftCaret:)];
    rightSwipeShiftCaret.direction = UISwipeGestureRecognizerDirectionRight;
    [tv addGestureRecognizer:rightSwipeShiftCaret];
    [rightSwipeShiftCaret release];

    SCSwipeGestureRecognizer *leftSwipeShiftCaret = [[SCSwipeGestureRecognizer alloc] initWithTarget:tv action:@selector(leftSwipeShiftCaret:)];
    leftSwipeShiftCaret.direction = UISwipeGestureRecognizerDirectionLeft;
    [tv addGestureRecognizer:leftSwipeShiftCaret];
    [leftSwipeShiftCaret release];
  }
}

static void InstallPanGestureRecognizer()
{
  if ([tv isKindOfClass:[UIView class]]) {
    SCPanGestureRecognizer *pan = [[SCPanGestureRecognizer alloc] initWithTarget:tv action:@selector(SCPanGestureDidPan:)];
    pan.cancelsTouchesInView = NO;
    [tv addGestureRecognizer:pan];
    [pan release];
  }
}

static void ShiftCaret(BOOL isLeftSwipe)
{
  if (panGestureEnabled)
    return;

  UITextPosition *position = nil;
  if ([tv respondsToSelector:@selector(positionFromPosition:inDirection:offset:)])
    position = isLeftSwipe ? [tv positionFromPosition:tv.selectedTextRange.start inDirection:UITextLayoutDirectionLeft offset:1]
      : [tv positionFromPosition:tv.selectedTextRange.end inDirection:UITextLayoutDirectionRight offset:1];
  // failsafe for over edge position crash.
  if (!position)
    return;
  UITextRange *range = [tv textRangeFromPosition:position toPosition:position];
  tv.selectedTextRange = range;
}

%hook UIView
- (BOOL)becomeFirstResponder
{
  BOOL tmp = %orig;
  if (tmp && [self respondsToSelector:@selector(setSelectedTextRange:)]) {
    tv = self;
    if (panGestureEnabled)
      InstallPanGestureRecognizer();
    else
      InstallSwipeGestureRecognizer();
  }
  return tmp;
}

%new(v@:@)
- (void)leftSwipeShiftCaret:(UISwipeGestureRecognizer *)gesture
{
  ShiftCaret(YES);
}

%new(v@:@)
- (void)rightSwipeShiftCaret:(UISwipeGestureRecognizer *)gesture
{
  ShiftCaret(NO);
}

// based code is SwipeSelection.
%new(v@:@)
- (void)SCPanGestureDidPan:(UIPanGestureRecognizer *)gesture
{
  if (!panGestureEnabled)
    return;

  static BOOL hasStarted = NO;
  static BOOL shiftHeldDown = NO;
  static BOOL isLeftPanning = YES;
  static UITextRange *startTextRange;
  static int numberOfTouches = 0;

  int touchesCount = [gesture numberOfTouches];
  if (touchesCount > numberOfTouches)
    numberOfTouches = touchesCount;

  UIKeyboardImpl *keyboardImpl = [%c(UIKeyboardImpl) sharedInstance];
  if ([keyboardImpl respondsToSelector:@selector(callLayoutIsShiftKeyBeingHeld)] && !shiftHeldDown)
    shiftHeldDown = [keyboardImpl callLayoutIsShiftKeyBeingHeld];

  if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
    numberOfTouches = 0;
    shiftHeldDown = NO;
    isLeftPanning = YES;
    hasStarted = NO;
    gesture.cancelsTouchesInView = NO;
    [startTextRange release];
    startTextRange = nil;
  } else if (gesture.state == UIGestureRecognizerStateBegan) {
    if ([tv respondsToSelector:@selector(positionFromPosition:inDirection:offset:)])
      startTextRange = [tv.selectedTextRange retain];
  } else if (gesture.state == UIGestureRecognizerStateChanged) {
    CGPoint offset = [gesture translationInView:self];
    if (!hasStarted && offset.x < 5 && offset.x > -5)
      return;
    if (!hasStarted)
      isLeftPanning = offset.x < 0 ? YES : NO;
    gesture.cancelsTouchesInView = YES;
    hasStarted = YES;
    int scale = 16 / numberOfTouches;
    int pointsChanged = offset.x / scale;

    UITextPosition *position = nil;
    if ([tv respondsToSelector:@selector(positionFromPosition:inDirection:offset:)]) {
      if (startTextRange.isEmpty)
        position = [tv positionFromPosition:startTextRange.start
          inDirection:pointsChanged < 0 ? UITextLayoutDirectionLeft : UITextLayoutDirectionRight
          offset:abs(pointsChanged)];
      else
        position = [tv positionFromPosition:isLeftPanning ? startTextRange.start : startTextRange.end
          inDirection:pointsChanged < 0 ? UITextLayoutDirectionLeft : UITextLayoutDirectionRight
          offset:abs(pointsChanged)];
    }
    // failsafe for over edge position crash.
    if (!position)
      return;

    UITextRange *range;
    if (!shiftHeldDown)
      range = [tv textRangeFromPosition:position toPosition:position];
    else {
      if (startTextRange.isEmpty)
        range = [tv textRangeFromPosition:startTextRange.start toPosition:position];
      else
        range = [tv textRangeFromPosition:isLeftPanning ? startTextRange.end : startTextRange.start toPosition:position];
    }
    tv.selectedTextRange = range;
  }
}
%end

static void LoadSettings()
{	
  NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
  id existPanGesture = [dict objectForKey:@"PanGestureEnabled"];
  panGestureEnabled = existPanGesture ? [existPanGesture boolValue] : YES;
  if (panGestureEnabled)
    InstallPanGestureRecognizer();
  else
    InstallSwipeGestureRecognizer();
}

static void PostNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
  LoadSettings();
}

%ctor
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PostNotification, CFSTR("jp.r-plus.swipeshiftcaret.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
  LoadSettings();
  [pool drain];
}
