; Exam Routine Widget - per-user installer (no admin required).
; Build with:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" .\installer\ExamRoutineWidget.iss
; Output: dist\ExamRoutineWidget-<version>-Setup.exe

#define MyAppName "Exam Routine Widget"
#define MyAppVersion Trim(FileRead(FileOpen("..\version.txt")))
#define MyAppPublisher "Hermesione"
#define MyAppUrl "https://github.com/Hermesione/exam-routine-widget"
#define MyAppExeName "Start Exam Widget.vbs"
#define MyEditorExeName "Edit Exam Routine.vbs"

[Setup]
AppId={{43F6A9E6-6B4F-4B36-9E4C-2E7A5D0C1A21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppUrl}
AppSupportURL={#MyAppUrl}
AppUpdatesURL={#MyAppUrl}
DefaultDirName={localappdata}\Programs\ExamRoutineWidget
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=ExamRoutineWidget-{#MyAppVersion}-Setup
SetupIconFile=..\assets\exam.ico
UninstallDisplayIcon={app}\assets\exam.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
LicenseFile=..\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "autostart"; Description: "Start the widget when &Windows starts"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "..\ExamWidget.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ExamEditor.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Start Exam Widget.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Edit Exam Routine.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\lib\*.ps1"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "..\assets\exam.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\docs\*.png"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\version.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Edit Exam Routine"; Filename: "{app}\{#MyEditorExeName}"; IconFilename: "{app}\assets\exam.ico"; WorkingDir: "{app}"
Name: "{group}\Start Exam Widget"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\exam.ico"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\exam.ico"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\exam.ico"; WorkingDir: "{app}"; Tasks: autostart

[Run]
Filename: "{app}\{#MyEditorExeName}"; Description: "Open the exam editor"; Flags: postinstall shellexec nowait

[UninstallDelete]
; Keep the user's data folder (exams, settings, backups). Remove only transient output.
Type: files; Name: "{app}\widget.log"
Type: files; Name: "{app}\data\edit-layout.request"
