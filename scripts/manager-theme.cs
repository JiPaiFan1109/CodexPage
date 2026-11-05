using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace DynamicSkin {
 public sealed class ThemeController {
  private sealed class ColorTarget {
   public Animatable Target; public DependencyProperty Property; public Color Day; public Color Night;
  }
  private readonly List<ColorTarget> colors=new List<ColorTarget>();
  private readonly List<AnimationClock> clocks=new List<AnimationClock>();
  private readonly ToggleButton toggle;
  private readonly TranslateTransform slide;
  private readonly List<UIElement[]> brands=new List<UIElement[]>();
  public event EventHandler ThemeChanged;
  private bool disposed;
  public bool ReduceMotion {get;set;}
  public bool IsNight {get;private set;}
  public int Changes {get;private set;}
  public double ThumbX {get{return slide.X;}}
  public double LastDuration {get;private set;}
  public ThemeController(ToggleButton button) {
   toggle=button;
   toggle.ApplyTemplate();
   slide=(TranslateTransform)toggle.Template.FindName("ThemeThumbTransform",toggle);
   toggle.Checked+=OnChanged; toggle.Unchecked+=OnChanged;
  }
  public void Add(Animatable target,DependencyProperty property,string day,string night) {
   colors.Add(new ColorTarget {Target=target,Property=property,Day=(Color)ColorConverter.ConvertFromString(day),Night=(Color)ColorConverter.ConvertFromString(night)});
  }
  public void AddBrand(UIElement light, UIElement dark) {brands.Add(new UIElement[] {light,dark});}
  private void OnChanged(object sender,RoutedEventArgs e) { Apply(toggle.IsChecked==true,true);if(ThemeChanged!=null) ThemeChanged(this,EventArgs.Empty); }
  private AnimationClock Clock(AnimationTimeline timeline) {
   AnimationClock clock=(AnimationClock)timeline.CreateClock(true);
   clock.Controller.Begin();clock.Controller.SeekAlignedToLastTick(TimeSpan.Zero,TimeSeekOrigin.BeginTime);
   clocks.Add(clock);return clock;
  }
  private void Number(DependencyObject target,DependencyProperty prop,double value,bool animate) {
   double current=(double)target.GetValue(prop);
   var animatable=target as Animatable;var element=target as UIElement;
   target.SetValue(prop,value);
   AnimationClock clock=null;
   if(animate) clock=Clock(new DoubleAnimation(current,value,TimeSpan.FromMilliseconds(300)) {EasingFunction=new CubicEase {EasingMode=EasingMode.EaseInOut},FillBehavior=FillBehavior.Stop});
   if(animatable!=null) animatable.ApplyAnimationClock(prop,clock,HandoffBehavior.SnapshotAndReplace);
   else element.ApplyAnimationClock(prop,clock,HandoffBehavior.SnapshotAndReplace);
  }
  public void Apply(bool night,bool animate) {
   // Take each current animated value before replacement; rapid reversal never snaps.
   animate=animate && !ReduceMotion && SystemParameters.ClientAreaAnimation;
   var previous=clocks.ToArray();clocks.Clear();IsNight=night;Changes++;LastDuration=animate?300:0;
   foreach(var entry in colors) {
    Color current=(Color)entry.Target.GetValue(entry.Property),destination=night?entry.Night:entry.Day;
    entry.Target.SetValue(entry.Property,destination);
    if(animate) {
     var animation=new ColorAnimation(current,destination,TimeSpan.FromMilliseconds(300)) {EasingFunction=new CubicEase {EasingMode=EasingMode.EaseInOut},FillBehavior=FillBehavior.Stop};
     entry.Target.ApplyAnimationClock(entry.Property,Clock(animation),HandoffBehavior.SnapshotAndReplace);
    } else {
     // Keep template resources mutable even when WPF seals a later card template.
     entry.Target.ApplyAnimationClock(entry.Property,Clock(new ColorAnimation(destination,destination,TimeSpan.Zero)),HandoffBehavior.SnapshotAndReplace);
    }
   }
   Number(slide,TranslateTransform.XProperty,night?46:0,animate);
   foreach(var brand in brands) {Number(brand[0],UIElement.OpacityProperty,night?0:1,animate);Number(brand[1],UIElement.OpacityProperty,night?1:0,animate);}
   foreach(var oldClock in previous) oldClock.Controller.Remove();
   AutomationProperties.SetName(toggle,night?"黑夜模式，切换到白天":"白天模式，切换到黑夜");
   toggle.ToolTip=night?"切换到白天模式":"切换到黑夜模式";
  }
  // Same native animation clocks, sampled deterministically for the review artifact.
  public void Seek(double milliseconds) {
   foreach(var clock in clocks) {clock.Controller.Pause();clock.Controller.SeekAlignedToLastTick(TimeSpan.FromMilliseconds(milliseconds),TimeSeekOrigin.BeginTime);}
  }
  public void Dispose() {
   if(disposed)return;disposed=true;
   toggle.Checked-=OnChanged;toggle.Unchecked-=OnChanged;
   foreach(var clock in clocks) clock.Controller.Remove();clocks.Clear();colors.Clear();brands.Clear();ThemeChanged=null;
  }
 }
}
