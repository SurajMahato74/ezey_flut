adb connect 192.168.1.65:5555

# Ezeyway - Flutter Delivery 2



Instant Delivery, Simplified.


in the black backgroudn big of that imaeg and ifrom box, with the button to top ovelay gradient black to yellow add a fethc background image shop image from the vednor profile

## Features

- **Splash Screen**: Custom animated splash screen with progress indicator
- **Home Screen**: Complete delivery app interface with categories, products, and navigation
- **Material 3 Design**: Custom Material 3 theme with yellow primary color (#f5ea47)
- **Dark Theme**: Optimized for dark mode UI
- **Google Fonts**: Plus Jakarta Sans typography
- **Network Images**: Product images and banners loaded from network
- **Interactive Elements**: Functional buttons, search bar, and navigation

## Getting Started

### Prerequisites

- Flutter SDK (latest version)
- Dart SDK
- Android Studio / VS Code
- iOS development tools (for iOS builds)

### Installation

1. **Install Dependencies**
   ```bash
   flutter pub get
   ```

2. **Download Font Files** (Optional - Google Fonts handles this automatically)
   The app uses Plus Jakarta Sans from Google Fonts, which is loaded automatically.

3. **Run the App**
   ```bash
   flutter run
   ```

### Building for Production

**Android:**
```bash
flutter build apk --release
```

**iOS:**
```bash
flutter build ios --release
```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── theme/
│   └── app_theme.dart       # Material 3 theme configuration
└── screens/
    ├── splash_screen.dart   # Animated splash screen
    └── home_screen.dart     # Main home screen interface
```

## Design Implementation

### Colors
- **Primary**: #f5ea47 (Yellow)
- **Background (Light)**: #f8f8f5
- **Background (Dark/Splash)**: #222110
- **Background (Home)**: #121212

### Typography
- **Font Family**: Plus Jakarta Sans (via Google Fonts)
- **Weights**: 400, 500, 700, 800

### Key Features

1. **Splash Screen**
   - Background image overlay with black transparency
   - Animated app icon and text
   - Progress bar animation
   - Auto-navigation to home screen

2. **Home Screen**
   - Location header with delivery address
   - Search functionality
   - Horizontal scrollable banner cards
   - Category chips (Food, Groceries, Pharmacy, etc.)
   - Product grid with ratings and pricing
   - Bottom navigation bar

3. **Navigation**
   - Smooth transitions between screens
   - Proper Material design patterns
   - Back button handling

## Dependencies

- `flutter`: SDK
- `google_fonts`: For Plus Jakarta Sans font
- `cupertino_icons`: iOS-style icons

## Customization

### Theme Colors
Edit `lib/theme/app_theme.dart` to modify colors:
```dart
static const Color primaryColor = Color(0xFFF5EA47); // Change primary color
static const Color backgroundDark = Color(0xFF222110); // Change dark background
```

### App Metadata
- **Package**: com.ezeyway.app
- **Name**: Ezeyway
- **Version**: 1.0.0

## Troubleshooting

1. **Build Errors**: Run `flutter clean && flutter pub get`
2. **Font Loading**: Ensure internet connection for Google Fonts
3. **Network Images**: Check internet connectivity for product images
4. **Android**: Minimum SDK level 21 (Android 5.0)
5. **iOS**: Requires iOS 11.0 or later

## Development

The app is designed to be easily extensible:
- Add new screens in `lib/screens/`
- Modify theme in `lib/theme/`
- Add new dependencies in `pubspec.yaml`
- Update configuration in `android/` and `ios/` folders