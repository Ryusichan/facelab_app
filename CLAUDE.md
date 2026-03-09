# FaceLab - Virtual Makeup Studio

## Project Overview
iOS app that scans a user's face via ARKit/RealityKit to create a 3D mesh, then allows applying virtual makeup with various brushes.

## Tech Stack
- **Frontend**: Swift, SwiftUI, ARKit, RealityKit (iOS 17+)
- **Backend**: Supabase (Auth, PostgreSQL, Storage, Edge Functions)
- **Package Manager**: Swift Package Manager (SPM)
- **Min Target**: iOS 17.0, iPhone only

## Project Structure
```
FaceLab/
├── App/              # App entry point, ContentView, navigation
├── Views/
│   ├── AR/           # ARKit face scanning views
│   ├── Makeup/       # Makeup studio UI, brush tools
│   ├── Auth/         # Login/signup views
│   └── Components/   # Reusable UI components
├── Models/           # Data models (MakeupLook, BrushType, etc.)
├── Services/         # Supabase client, API services
├── Extensions/       # Swift extensions
└── Resources/        # Supabase.plist (secrets - gitignored)
```

## Key Conventions
- SwiftUI for all UI, UIViewRepresentable for ARView
- @MainActor for all ViewModels
- Supabase.plist holds secrets (gitignored) — never commit
- RLS (Row Level Security) on all Supabase tables
- Korean localization planned

## Build & Run
1. Open `FaceLab.xcodeproj` in Xcode 15+
2. Wait for SPM to resolve Supabase dependency
3. Configure `FaceLab/Resources/Supabase.plist` with your project URL + anon key
4. Run on physical device (ARKit face tracking requires TrueDepth camera)

## Supabase Setup
1. Create project at supabase.com
2. Run `supabase/migrations/001_initial_schema.sql` in SQL Editor
3. Create storage bucket "face-captures" (private, image/jpeg + image/png)
4. Copy project URL + anon key into Supabase.plist
