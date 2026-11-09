using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace DynamicSkin {
    // One muted player per realized video card; no media survives an unloaded card.
    public sealed class ThumbnailPlayback {
        static ThumbnailPlayback() {
            EventManager.RegisterClassHandler(typeof(MediaElement), FrameworkElement.LoadedEvent,
                new RoutedEventHandler(delegate(object sender, RoutedEventArgs args) { Attach((MediaElement)sender); }));
        }
        public static void Initialize() { }
        private static readonly DependencyProperty ControllerProperty = DependencyProperty.RegisterAttached(
            "Controller", typeof(ThumbnailPlayback), typeof(ThumbnailPlayback));
        private readonly MediaElement media;
        private readonly DispatcherTimer timer;
        private Window window;
        private bool failed;
        private string activePath;
        private ThumbnailPlayback(MediaElement element) {
            media = element;
            media.LoadedBehavior = MediaState.Manual;
            media.UnloadedBehavior = MediaState.Close;
            media.IsMuted = true;
            media.Volume = 0;
            media.Opacity = 0;
            timer = new DispatcherTimer(DispatcherPriority.Background, media.Dispatcher);
            timer.Interval = TimeSpan.FromMilliseconds(350);
            timer.Tick += delegate { Update(); };
            media.Loaded += delegate { Start(); };
            media.Unloaded += delegate { Detach(); };
            media.IsVisibleChanged += delegate { Update(); };
            media.IsEnabledChanged += delegate { Update(); };
            media.MediaOpened += delegate { if (media.Source != null) media.Opacity = 1; };
            media.MediaEnded += delegate { if (media.Source != null) { media.Position = TimeSpan.Zero; media.Play(); } };
            media.MediaFailed += delegate { failed = true; Close(); };
            Start();
        }
        public static void Attach(MediaElement media) {
            if (media == null || media.Name != "ThumbnailVideo" || media.GetValue(ControllerProperty) != null) return;
            media.SetValue(ControllerProperty, new ThumbnailPlayback(media));
        }
        private void Start() {
            if (!media.IsLoaded) return;
            if (window == null) {
                window = Window.GetWindow(media);
                if (window != null) { window.StateChanged += WindowChanged; window.Closed += WindowClosed; }
            }
            timer.Start();
            Update();
        }
        private void WindowChanged(object sender, EventArgs args) { Update(); }
        private void WindowClosed(object sender, EventArgs args) { Detach(); }
        private bool VisibleInViewport() {
            FrameworkElement boundsElement = media;
            DependencyObject parent = VisualTreeHelper.GetParent(media);
            while (parent != null) {
                // A source-less MediaElement can measure to zero until preroll.
                // Use its card's geometry to decide whether to open that source.
                if (parent is ListBoxItem) boundsElement = (ListBoxItem)parent;
                ScrollContentPresenter viewport = parent as ScrollContentPresenter;
                if (viewport != null) {
                    Rect bounds = boundsElement.TransformToAncestor(viewport).TransformBounds(new Rect(boundsElement.RenderSize));
                    if (!bounds.IntersectsWith(new Rect(viewport.RenderSize))) return false;
                }
                parent = VisualTreeHelper.GetParent(parent);
            }
            return boundsElement.ActualWidth > 0 && boundsElement.ActualHeight > 0;
        }
        private void Update() {
            string path = media.Tag as string;
            if (!String.Equals(path, activePath, StringComparison.OrdinalIgnoreCase)) {
                Close(); failed = false; activePath = path;
            }
            bool play = !String.IsNullOrEmpty(path) && !failed && media.IsLoaded && media.IsVisible && media.IsEnabled && window != null
                && window.WindowState != WindowState.Minimized && SystemParameters.ClientAreaAnimation;
            if (play) play = VisibleInViewport();
            if (!play) { Close(); return; }
            if (media.Source == null) {
                try { media.Source = new Uri(path, UriKind.Absolute); media.Play(); }
                catch { failed = true; Close(); }
            }
        }
        private void Close() {
            media.Opacity = 0;
            if (media.Source == null) return;
            media.Close();
            media.Source = null;
        }
        private void Detach() {
            timer.Stop();
            Close();
            if (window != null) { window.StateChanged -= WindowChanged; window.Closed -= WindowClosed; window = null; }
        }
    }
}
