unit Update.Utils;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Zip,
  Update.Types;

type

  TFolder = record

    class function Combine(const Path,FileName: string): string; static;
    class function GetAppPath: string; static;
    class function GetShareDataPath: string; static;
    class function GetDataPath(const AppName: string): string; static;
    class function GetLibraryPath: string; static;
    class function GetProgramsPath: string; static;
    class function GetTempPath: string; static;

    class function GetHomePath: string; static;
    class function GetSharedHomePath: string; static;
    class function GetDocumentsPath: string; static;
    class function GetSharedDocumentsPath: string; static;
    class function GetPicturesPath: string; static;
    class function GetSharedPicturesPath: string; static;
    class function GetDownloadsPath: string; static;
    class function GetSharedDownloadsPath: string; static;

    class procedure SetFileAttributesNormal(const FileName: string); static;
    class procedure CopyFile(const SourceFileName,DestFileName: string); static;
    class procedure MoveExists(const SourceDirectory,DestDirectory: string; DeleteSource: Boolean); static;
    class procedure DeleteFile(const FileName: string); static;

  end;

procedure OpenLink(const FileLink: string);
procedure OpenURL(const URL: string);
procedure CreateShortcutOnDesktop(const FilePath,Params,Name: string; Overwrite: Boolean);
function GetAppVersion: string;
function IsInstalledFromStore: Boolean;
function InstallPackage(const PackageApp: string): Boolean;
function UpdatePackage(const ExecuteApp,PackageApp: string): Boolean;

implementation

{$IFDEF MSWINDOWS}

uses
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, Winapi.ShellAPI,
  Winapi.KnownFolders, System.Win.ComObj;

function GetKnownFolderPath(const rfid: TIID): string;
var LStr: PChar;
begin
  if SHGetKnownFolderPath(rfid,0,0,LStr)=0 then
  begin
    Result:=LStr;
    CoTaskMemFree(LStr);
  end else
    Result := '';
end;

function GetFileVersion(const AFileName: string): string;
var
  FileName: string;
  InfoSize, Wnd: DWORD;
  VerBuf: Pointer;
  FI: PVSFixedFileInfo;
  VerSize: DWORD;
begin
  Result:='';
  // GetFileVersionInfo modifies the filename parameter data while parsing.
  // Copy the string const into a local variable to create a writeable copy.
  FileName:=AFileName;
  UniqueString(FileName);
  InfoSize:=GetFileVersionInfoSize(PChar(FileName),Wnd);
  if InfoSize<>0 then
  begin
    GetMem(VerBuf,InfoSize);
    try
      if GetFileVersionInfo(PChar(FileName),Wnd,InfoSize,VerBuf) then
      if VerQueryValue(VerBuf,'\',Pointer(FI),VerSize) then
        Result:=Format('%d.%d.%d',[HiWord(FI.dwFileVersionMS),LoWord(FI.dwFileVersionMS),HiWord(FI.dwFileVersionLS)]);
    finally
      FreeMem(VerBuf);
    end;
  end;
end;

{$ENDIF}

{$IFDEF ANDROID}

uses
  Androidapi.Helpers, Androidapi.JNI.Os, Androidapi.JNI.GraphicsContentViewText,
  Androidapi.JNI.JavaTypes, Androidapi.JNI.Webkit, Androidapi.JNI.Net, Androidapi.JNIBridge,
  Androidapi.JNI.App, Androidapi.JNI.Support, FMX.Platform.Android, Androidapi.JNI.Provider,
  Androidapi.JNI.Widget, Androidapi.JNI.Embarcadero, Androidapi.IOUtils,
  Dialogs.Android, SaveDialog.Android;

{$ENDIF}

{$IFDEF MACOS}

{$IFDEF IOS}

uses
  iOSapi.Foundation, FMX.Helpers.iOS, iOSapi.UIKit, Macapi.CoreFoundation,
  Macapi.Helpers, SaveDialog.iOS, Dialogs.iOS;

function GetIOSDeviceID: string;
var
  LDevice: UIDevice;
begin
  Result := '';
  LDevice := TUIDevice.Wrap(TUIDevice.OCClass.currentDevice);
  if LDevice <> nil then
    Result := NSStrToStr(LDevice.identifierForVendor.UUIDString);
end;

{$ELSE}

uses
  Macapi.Foundation, Macapi.AppKit, Macapi.CoreFoundation, Macapi.Helpers,
  Macapi.IOKit,
  Posix.Errno, Posix.SysStat, Posix.Unistd; // for InternalPosixFileGetAttr

function GetMacHDDSerialID: string;

// https://github.com/rzaripov1990/FMX.DeviceInfo

const
  kIOPlatformSerialNumberKey = 'IOPlatformSerialNumber';
var
  PlatformExpert: io_service_t;
  M: CFMutableDictionaryRef;
  CFTR: CFTypeRef;
  pac: PAnsiChar;
begin

  M:=IOServiceMatching('IOPlatformExpertDevice');

  PlatformExpert:=IOServiceGetMatchingService(kIOMasterPortDefault,CFDictionaryRef(M));

  try

    CFTR:=IORegistryEntryCreateCFProperty(PlatformExpert,
      CFSTR(kIOPlatformSerialNumberKey),kCFAllocatorDefault,0);

    pac:=CFStringGetCStringPtr(CFTR,0);

    Result:=AnsiString(pac);

  finally
    IOObjectRelease(PlatformExpert);
  end;

end;

// code from System.SysUtils

function InternalPosixFileGetAttr(const FileName: string; FollowLink: Boolean;
  var StatBuf: _stat): Integer;
var
  LinkStatBuf: _stat;
  OnlyName: string;
  L: Integer;
  M: TMarshaller;
  P: Pointer;
begin
  Result := faInvalid;
  P := M.AsAnsi(FileName, CP_UTF8).ToPointer;

  if (FollowLink and (stat(P, StatBuf) = 0)) or
    (not FollowLink and (lstat(P, StatBuf) = 0)) then
  begin
    Result := 0;

    if S_ISDIR(StatBuf.st_mode) then
      Result := faDirectory
    else if not S_ISREG(StatBuf.st_mode) and S_ISLNK(StatBuf.st_mode) then
    begin
      Result := Result or faSymLink;

      if (stat(P, LinkStatBuf) = 0) and
        S_ISDIR(LinkStatBuf.st_mode) then
      begin
        Result := Result or faDirectory;
      end;
    end;
    if euidaccess(P, W_OK) <> 0 then
      Result := Result or faReadOnly;

    OnlyName := ExtractFilename(FileName);
    L := OnlyName.Length;

    if (L > 1) and (OnlyName.Chars[0] = '.') and (OnlyName.Chars[1] <> #0) then
    begin
      if (L > 3) and not ((OnlyName.Chars[1] = '.') and (OnlyName.Chars[2] = #0)) then
        Result := Result or faHidden;
    end;
  end;
end;

{$ENDIF}

function GetMacApplicationSupportDirectory: string;
var
  URL: NSURL;
  BundleIdentifier: string;
begin

  URL:=TNSFileManager.Wrap(TNSFileManager.OCClass.defaultManager).URLForDirectory(
    NSApplicationSupportDirectory,NSUserDomainMask,nil,True,nil);

  if URL<>nil then
    Result:=UTF8ToString(URL.path.UTF8String)
  else
    Result:=TPath.GetLibraryPath;

  BundleIdentifier:=NSStrToStr(TNSBundle.Wrap(TNSBundle.OCClass.mainBundle).bundleIdentifier);

  Panic(BundleIdentifier='','undefined CFBundleIdentifier');

  Result:=TPath.Combine(Result,BundleIdentifier);

end;

{$ENDIF}

{$IFDEF LINUX}

uses
  Posix.Fcntl,Posix.Stdlib,Posix.SysStatvfs, Posix.Unistd;

{$ENDIF}

class function TFolder.Combine(const Path,FileName: string): string;
begin
  Result:=TPath.Combine(Path,FileName);
end;

class function TFolder.GetAppPath: string;
{$IFDEF LINUX}
var Buffer: array [0..MAX_PATH] of Char;
begin
  SetString(Result,Buffer,GetModuleFileName(0,Buffer,Length(Buffer)));
end;
{$ELSE}
begin
  {$IFDEF ANDROID}
  Result:=JStringToString(SharedActivityContext.getPackageCodePath);
  {$ELSE}
  Result:=ParamStr(0);
  {$ENDIF}
end;
{$ENDIF}

class function TFolder.GetShareDataPath: string;
begin

  {$IFDEF MSWINDOWS}
  Result:=TPath.GetPublicPath;
  {$ELSE}
  Result:=TFolder.GetSharedDownloadsPath;
  {$ENDIF}

end;

class function TFolder.GetDataPath(const AppName: string): string;
begin

  {$IFDEF MSWINDOWS}
  Result:=TPath.GetLibraryPath;
  {$ENDIF}

  {$IFDEF ANDROID}
  Result:=TPath.GetDocumentsPath;
  {$ENDIF}

  {$IFDEF MACOS}{$IFDEF IOS}
  Result:=TPath.GetDocumentsPath;
  {$ELSE}
  Result:=GetMacApplicationSupportDirectory;
  {$ENDIF}{$ENDIF}

  {$IFDEF LINUX}
  Result:=Combine(GetHomePath,'.'+AppName);
  {$ENDIF}

end;

class function TFolder.GetLibraryPath: string;
begin
  Result:=TPath.GetLibraryPath;
end;

class function TFolder.GetTempPath: string;
begin
  Result:=TPath.GetTempPath;
end;

class function TFolder.GetProgramsPath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:='C:\Programs';
  {$ENDIF}
  {$IFDEF LINUX}
  Result:=Combine(TPath.GetHomePath,'Programs');
  {$ENDIF}
end;

class function TFolder.GetHomePath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:=GetKnownFolderPath(FOLDERID_Profile);
  {$ENDIF}
  if Result='' then Result:=TPath.GetHomePath;
end;

class function TFolder.GetSharedHomePath: string;
begin
  Result:=GetHomePath;
end;

class function TFolder.GetDocumentsPath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:=GetKnownFolderPath(FOLDERID_Documents);
  {$ENDIF}
  if Result='' then Result:=TPath.GetDocumentsPath;
end;

class function TFolder.GetSharedDocumentsPath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:=GetKnownFolderPath(FOLDERID_Documents);
  {$ENDIF}
  if Result='' then Result:=TPath.GetSharedDocumentsPath;
end;

class function TFolder.GetPicturesPath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:=GetKnownFolderPath(FOLDERID_Pictures);
  {$ENDIF}
  if Result='' then Result:=TPath.GetPicturesPath;
end;

class function TFolder.GetSharedPicturesPath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:=GetKnownFolderPath(FOLDERID_Pictures);
  {$ENDIF}
  if Result='' then Result:=TPath.GetSharedPicturesPath;
end;

class function TFolder.GetDownloadsPath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:=GetKnownFolderPath(FOLDERID_Downloads);
  {$ENDIF}
  if Result='' then Result:=TPath.GetDownloadsPath;
end;

class function TFolder.GetSharedDownloadsPath: string;
begin
  Result:='';
  {$IFDEF MSWINDOWS}
  Result:=GetKnownFolderPath(FOLDERID_Downloads);
  {$ENDIF}
  {$IFDEF IOS}
  Result:=TPath.GetCachePath;
  {$ENDIF}
  if Result='' then Result:=TPath.GetSharedDownloadsPath;
end;

class procedure TFolder.CopyFile(const SourceFileName,DestFileName: string);
begin

  SetFileAttributesNormal(DestFileName); // no except if file not exist

  TFile.Copy(SourceFileName,DestFileName,True);

end;

class procedure TFolder.MoveExists(const SourceDirectory,DestDirectory: string;
  DeleteSource: Boolean);
begin

  if TDirectory.Exists(SourceDirectory) then

  if not TDirectory.Exists(DestDirectory) then

    TDirectory.Move(SourceDirectory,DestDirectory)

  else

  if DeleteSource then

    TDirectory.Delete(SourceDirectory,True);

end;

class procedure TFolder.SetFileAttributesNormal(const FileName: string);
begin

  {$IFDEF MSWINDOWS}
  // clear read-only, system and hidden attributes that can compromise the deletion or overwrite
  FileSetAttr(FileName,faNormal);
  {$ENDIF MSWINDOWS}

end;

class procedure TFolder.DeleteFile(const FileName: string);
begin

  SetFileAttributesNormal(FileName);

  TFile.Delete(FileName);

end;

function IsInstalledFromStore: Boolean;
begin

  Result:=False;

  {$IFDEF ANDROID}

  // https://stackoverflow.com/questions/10809438/how-to-know-an-application-is-installed-from-google-play-or-side-load

  var AppContext:=TAndroidHelper.Context;

  if AppContext<>nil then
  begin
    var PackageManager:=AppContext.getPackageManager;
    if PackageManager<>nil then
      Result:=not JStringToString(AppContext.getPackageManager.getInstallerPackageName(AppContext.getPackageName)).isEmpty;
  end;

  {$ENDIF}

  {$IFDEF IOS}

  Result:=True;

  {$ENDIF}

end;

procedure CreateShortcutOnDesktop(const FilePath,Params,Name: string; Overwrite: Boolean);
{$IFDEF MSWINDOWS}
var
  ShortcutPath: string;
  ShellLink: IShellLink;
begin

  if Name.IsEmpty then
    ShortcutPath:=TPath.GetFileNameWithoutExtension(FilePath)
  else
    ShortcutPath:=Name;

  ShortcutPath:=TPath.Combine(GetKnownFolderPath(FOLDERID_Desktop),ShortcutPath+'.lnk');

  if Overwrite or not TFile.Exists(ShortcutPath) then
  begin

    OleCheck(CoCreateInstance(CLSID_ShellLink,nil,CLSCTX_INPROC_SERVER,IShellLink,ShellLink));

    OleCheck(ShellLink.SetPath(PChar(FilePath)));
    OleCheck(ShellLink.SetWorkingDirectory(PChar(TPath.GetDirectoryName(FilePath))));
    OleCheck(ShellLink.SetArguments(PChar(Params)));

    OleCheck((ShellLink as IPersistFile).Save(PChar(ShortcutPath),True));

  end;

end;
{$ELSE}
begin

end;
{$ENDIF}

{$IFDEF MSWINDOWS}

function GetAppVersion: string;
begin
  Result:=GetFileVersion(TFolder.GetAppPath);
end;

{$ELSE}

{$IFDEF LINUX}

function GetAppVersion: string;
begin
  Result:={$I linux-version.inc};
end;

{$ELSE}

function GetAppVersion: string;
begin
  Result:=IFMXApplicationService(TPlatformServices.Current.GetPlatformService(IFMXApplicationService)).AppVersion;
end;

{$ENDIF}

{$ENDIF}

function FileIs(const FileName,Ext: string): Boolean;
begin
  Result:=FileName.EndsWith(Ext,True);
end;

procedure Unzip(const ZipFileName,DestPath: string);
begin
  var ZipFile:=TZipFile.Create;
  AddRelease(ZipFile);
  ZipFile.Open(ZipFileName,TZipMode.zmRead);
  for var FileName in ZipFile.FileNames do ZipFile.Extract(FileName,DestPath);
end;

function UnzipThis(const ZipFileName,ThisFileName,DestPath: string): Boolean;
begin

  var ZipFile:=TZipFile.Create;

  AddRelease(ZipFile);

  ZipFile.Open(ZipFileName,TZipMode.zmRead);

  for var FileName in ZipFile.FileNames do
  if string.Compare(FileName,ThisFileName,True)=0 then
  begin
    ZipFile.Extract(FileName,DestPath);
    Exit(True);
  end;

  Result:=False;

end;

{$IFDEF MSWINDOWS}

function Exec(const Command: string; ShowWindow: UINT): Boolean;
var
  ProcessInformation: TProcessInformation;
  StartupInfo: TStartupInfo;
begin

  StartupInfo:=Default(TStartupInfo);

  StartupInfo.lpDesktop:=nil;
  StartupInfo.lpTitle:=nil;
  StartupInfo.dwFlags:=STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow:=ShowWindow;

  Result:=CreateProcess(nil,PWideChar(Command),nil,nil,False,CREATE_DEFAULT_ERROR_MODE,
    nil,nil,StartupInfo,ProcessInformation);

end;

function InstallZipPackage(const PackageApp: string): Boolean;
begin

  var AppPath:=TFolder.GetAppPath;
  var ExeFileName:=ExtractFileName(AppPath);
  var PackagePath:=ExtractFilePath(PackageApp);
  var PackageExeFile:=TFolder.Combine(PackagePath,ExeFileName);

  Result:=UnzipThis(PackageApp,ExeFileName,PackagePath) and
    Exec(string.Join(' ',[PackageExeFile.QuotedString('"'),'update',
      AppPath.QuotedString('"'),PackageApp.QuotedString('"')]),SW_SHOW);

end;

function InstallExePackage(const PackageApp: string): Boolean;
begin
  Result:=Exec(string.Join(' ',[PackageApp.QuotedString('"'),'update',
    TFolder.GetAppPath.QuotedString('"')]),SW_SHOW);
end;

function InstallPackage(const PackageApp: string): Boolean;
begin
  if FileIs(PackageApp,'.zip') then
    Result:=InstallZipPackage(PackageApp)
  else
  if FileIs(PackageApp,'.exe') then
    Result:=InstallExePackage(PackageApp)
  else
    Result:=False;
end;

function UpdatePackage(const ExecuteApp,PackageApp: string): Boolean;
var
  C: Integer;
  PackageFileName: string;
  LastError: DWORD;
begin

  C:=0;
  Result:=False;
  LastError:=0;
  PackageFileName:=TFolder.GetAppPath;

  while (C<10) and FileExists(PackageFileName) and FileExists(ExecuteApp) do
  begin
    Inc(C);
    Sleep(3000);
    if CopyFileEx(PWideChar(PackageFileName),PWideChar(ExecuteApp),nil,nil,nil,0) then
      Exit(Exec(string.Join(' ',[ExecuteApp.QuotedString('"'),'updated']),SW_SHOW));
    LastError:=GetLastError;
  end;

  CheckOSError(LastError);

end;

procedure OpenLink(const FileLink: string);
begin
  ShellExecute(0,'open',PChar(FileLink),nil,nil,SW_SHOWDEFAULT);
end;

procedure OpenURL(const URL: string);
begin
  OpenLink(URL);
end;

{$ENDIF}

{$IFDEF ANDROID}

function InstallPackage(const PackageApp: string): Boolean;
begin
  Result:=True;
  OpenIntent(PackageApp,TJIntent.JavaClass.ACTION_INSTALL_PACKAGE);
end;

function UpdatePackage(const ExecuteApp,PackageApp: string): Boolean;
begin
  Result:=True;
end;

procedure OpenLink(const FileLink: string);
begin
  OpenIntent(FileLink,TJIntent.JavaClass.ACTION_VIEW);
end;

procedure OpenURL(const URL: string);
var
  Intent: JIntent;
begin

  Intent:=TJIntent.Create;

  Intent.setAction(TJIntent.JavaClass.ACTION_VIEW);
  Intent.addCategory(TJIntent.JavaClass.CATEGORY_BROWSABLE);
  Intent.setData(StrToJURI(URL));

  MainActivity.startActivity(Intent);

end;

{$ENDIF}

{$IFDEF MACOS}

{$IFDEF IOS}

procedure OpenLink(const FileLink: string);
begin

  iOSPreviewFile(FileLink);
end;

procedure OpenURL(const URL: string);
var _NSUrl: NSURL;
begin
  _NSUrl:=TNSUrl.Wrap(TNSUrl.OCClass.URLWithString(NSStr(URL)));
  SharedApplication.openUrl(_NSUrl);
end;

function InstallPackage(const PackageApp: string): Boolean;
begin
  Result:=False;
end;

function UpdatePackage(const ExecuteApp,PackageApp: string): Boolean;
begin
  Result:=False;
end;

{$ELSE}

procedure OpenLink(const FileLink: string);
begin
  TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace).openFile(NSStr(FileLink));
end;

procedure OpenURL(const URL: string);
var _NSUrl: NSURL;
begin
  _NSUrl:=TNSUrl.Wrap(TNSUrl.OCClass.URLWithString(NSStr(URL)));
  TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace).openURL(_NSUrl);
end;

function InstallPackage(const PackageApp: string): Boolean;
begin

  Result:=True;

  OpenLink(PackageApp);

//  var NSTask: TNSTask;
//  NSTask.setLaunchPath(StrToNSStr(PackageApp));
//  NSTask.parameters:=
//  NSTask.launch;

end;

function UpdatePackage(const ExecuteApp,PackageApp: string): Boolean;
begin
  Result:=False;
end;

{$ENDIF}

{$ENDIF}

{$IFDEF LINUX}

procedure Exec(const FileLink: string);
var
  M: TMarshaller;
  A: TArray<PAnsiChar>;
begin

  var I:=0;
  var P:=FileLink.Split([' ']);

  SetLength(A,Length(P)+1);

  for var S in P do
  begin
    A[I]:=M.AsUtf8(S).ToPointer;
    Inc(I);
  end;

  A[I]:=nil;

  execve(A[0],M.FixArray<PAnsiChar>(A).ToPointer,nil);

end;

procedure OpenLink(const FileLink: string);
var M: TMarshaller;
begin
 _system(M.AsAnsi(FileLink+' &',CP_UTF8).ToPointer);
end;

procedure OpenURL(const URL: string);
begin
end;

function InstallZipPackage(const PackageApp: string): Boolean;
begin

  var AppPath:=TFolder.GetAppPath;
  var ExeFileName:=ExtractFileName(AppPath);
  var PackagePath:=ExtractFilePath(PackageApp);
  var PackageExeFile:=TFolder.Combine(PackagePath,ExeFileName);

  Result:=UnzipThis(PackageApp,ExeFileName,PackagePath);

  if Result then
  begin
    TFile.SetAttributes(PackageExeFile,TFile.GetAttributes(AppPath));
    Exec(string.Join(' ',[PackageExeFile,'update',AppPath,PackageApp]));
  end;

end;

function InstallExePackage(const PackageApp: string): Boolean;
begin
  Result:=True;
  var ExecutePath:=TFolder.GetAppPath;
  TFile.SetAttributes(PackageApp,TFile.GetAttributes(ExecutePath));
  Exec(PackageApp+' update '+ExecutePath);
end;

function InstallPackage(const PackageApp: string): Boolean;
begin
  if FileIs(PackageApp,'.zip') then
    Result:=InstallZipPackage(PackageApp)
  else
    Result:=InstallExePackage(PackageApp);
end;

function UpdatePackage(const ExecuteApp,PackageApp: string): Boolean;
begin

  Result:=True;

  var ExeAttributes:=TFile.GetAttributes(ExecuteApp);

  TFile.Delete(ExecuteApp);

  if FileIs(PackageApp,'.zip') then
    Unzip(PackageApp,ExtractFilePath(ExecuteApp))
  else
    TFile.Copy(PackageApp,ExecuteApp);

  TFile.SetAttributes(ExecuteApp,ExeAttributes);

  Exec(ExecuteApp+' updated');

end;

{$ENDIF}

end.
