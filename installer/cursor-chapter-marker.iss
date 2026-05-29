; Inno Setup script for Cursor Chapter Marker OBS Plugin
; Compile with: iscc cursor-chapter-marker.iss
; Requires: Inno Setup 6+ (https://jrsoftware.org/isdl.php)

#define MyAppName    "Cursor Chapter Marker"
#define MyAppVer     "1.0.0"
#define MyAppPublish "Juliano Ouvrard"
#define MyDllSource  "..\build_x64\cursor-chapter-marker.dll"
#define MyDataSource "..\data"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVer}
AppPublisher={#MyAppPublish}
AppId={{A7F3C2D1-BE48-4E9A-B0F5-12E3D456789A}
DefaultDirName={autopf}\obs-studio
DefaultGroupName={#MyAppName}
DisableDirPage=yes
OutputDir=..\dist
OutputBaseFilename=cursor-chapter-marker-{#MyAppVer}-windows-x64-installer
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\obs-plugins\64bit\cursor-chapter-marker.dll

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french";  MessagesFile: "compiler:Languages\French.isl"

[Messages]
english.WelcomeLabel2=This will install [name/ver] for OBS Studio.%n%nMake sure OBS Studio is installed before continuing.
french.WelcomeLabel2=Ceci va installer [name/ver] pour OBS Studio.%n%nAssurez-vous qu'OBS Studio est installé avant de continuer.

[Files]
; Plugin DLL
Source: "{#MyDllSource}"; DestDir: "{app}\obs-plugins\64bit"; Flags: ignoreversion

; Locale data
Source: "{#MyDataSource}\locale\*"; DestDir: "{app}\data\obs-plugins\cursor-chapter-marker\locale"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; No shortcuts needed for a plugin

[Run]
; Nothing to run after install

[Code]
// Verify OBS Studio is installed in the chosen directory
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    if not FileExists(ExpandConstant('{app}\bin\64bit\obs64.exe')) then begin
      MsgBox('OBS Studio does not appear to be installed in the selected folder.'#13#10 +
             'Please select the correct OBS Studio installation folder.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

// Try to detect OBS Studio installation path from registry
function InitializeSetup(): Boolean;
var
  obsPath: String;
begin
  Result := True;
  if RegQueryStringValue(HKLM, 'SOFTWARE\OBS Studio', '', obsPath) then begin
    WizardForm.DirEdit.Text := obsPath;
  end;
end;
