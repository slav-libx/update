unit Update.Core;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Classes,
  System.DateUtils,
  System.Math,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SyncObjs,
  Update.Types,
  Update.Utils;

type
  TUpdateCore = class
  private
    FUpdatesRef: string;
    FAppPath: string;
    FAppVersion: string;
    FAppDate: TDateTime;
    FAvailableVersion: string;
    FAvailableDescription: string;
    FAvailableDate: Int64;
    FDownloadsPath: string;
    DownloadPackage: string;
    URIPackage: string;
    FThread: TThread;
    FEvent: TEvent;
    procedure OnReadUpdatesAsyncTerminate(Sender: TObject);
    procedure GetAvailableUpdates;
    procedure DownloadUpdatePackage;
    procedure DoReadUpdatesAsync;
    function AppRunAsUpdater: Boolean;
  public
    constructor Create(const UpdatesRef: string);
    destructor Destroy; override;
    procedure StartUpdate;
    property AppPath: string read FAppPath;
    property AppVersion: string read FAppVersion;
    property AppDate: TDateTime read FAppDate;
  end;

var
  UpdateCore: TUpdateCore;

implementation

const
  MINUTE = 60*1000;
  HOUR = 60*MINUTE;
  CHECK_LOW = 24*HOUR;
  CHECK_HIGH = 10*MINUTE;

  PACKAGE_IDENTITY =
    {$IFDEF MSWINDOWS}'windows-'{$ENDIF}
    {$IFDEF ANDROID}'android-'{$ENDIF}
    {$IFDEF MACOS}{$IFDEF IOS}'ios-'{$ELSE}'macos-'{$ENDIF}{$ENDIF}
    {$IFDEF LINUX}'linux-'{$ENDIF}
    {$IFDEF CONSOLE}+'console-'{$ELSE}
      {$IFDEF MSWINDOWS}+'desktop-'{$ENDIF}
      {$IFDEF ANDROID}+'mobile-'{$ENDIF}
      {$IFDEF MACOS}{$IFDEF IOS}+'mobile-'{$ELSE}+'desktop-'{$ENDIF}{$ENDIF}
      {$IFDEF LINUX}+'desktop-'{$ENDIF}
    {$ENDIF}
    {$IFDEF CPU32BITS}+'x32'{$ELSE}+'x64'{$ENDIF};

procedure ToLog(const S: string);
begin
  {$IFDEF CONSOLE}
  Writeln(S);
  {$ENDIF}
end;

function CompareVersion(const Version1,Version2: string): Integer;

// Version1>Version2 --> Result>0
// Version1<Version2 --> Result<0
// Version1=Version2 --> Result=0

var V1,V2: Int64;
begin

  Result:=0;

  var A1:=Version1.Split(['.']);
  var A2:=Version2.Split(['.']);

  for var I:=Low(A1) to Min(High(A1),High(A2)) do
  if Result=0 then
    if TryStrToInt64(A1[I],V1) then
      if TryStrToInt64(A2[I],V2) then
        Result:=V1-V2
      else Result:=CompareStr(A1[I],A2[I])
    else Result:=CompareStr(A1[I],A2[I])
  else Exit;

end;

function ToGMTTime(Date: TDateTime): string;
begin
  Result:=FormatDateTime('ddd, dd mmm yyyy hh:nn:ss "GMT"',
    TTimeZone.Local.ToUniversalTime(Date),TFormatSettings.Create('en-US'));
end;

function FromGMTTime(const GMTTime: string): TDateTime;
begin
  Result:=TCookie.Create('id=; expires='+GMTTime,TURI.Create('http://com')).Expires;
end;

constructor TUpdateCore.Create(const UpdatesRef: string);
begin
  FUpdatesRef:=UpdatesRef;
  FDownloadsPath:=TFolder.GetDownloadsPath;
  FAppPath:=TFolder.GetAppPath;
  FAppVersion:=GetAppVersion;
  FAppDate:=TFile.GetLastWriteTime(FAppPath);
  FAvailableVersion:='';
  FAvailableDescription:='';
  FAvailableDate:=0;
  FEvent:=TEvent.Create;
  FEvent.ResetEvent;
end;

destructor TUpdateCore.Destroy;
begin
  FEvent.SetEvent;
  FThread.WaitFor;
  FThread.Free;
  FEvent.Free;
end;

function TUpdateCore.AppRunAsUpdater: Boolean;
begin

  Result:=False;

  {$IF DEFINED(LINUX) OR DEFINED(MSWINDOWS)}
  Result:=ParamStr(1)='update';
  {$ENDIF}

end;

procedure CheckResponse(R: IHTTPResponse);
begin
  if R.StatusCode<>200 then
  if R.StatusText.IsEmpty then
    Stop(R.StatusCode.ToString+' No Reason Phrase')
  else
    Stop(R.StatusText);
end;

procedure TUpdateCore.GetAvailableUpdates;
var JSONUpdates,JSONPackage: TJSONValue;
begin

  ToLog('Download update info');

  var ResponseContent:=TMemoryStream.Create;

  AddRelease(ResponseContent);

  var Client:=THTTPClient.Create;

  AddRelease(Client);

  try

    var Response:=Client.Get(FUpdatesRef,ResponseContent);

    CheckResponse(Response);

    JSONUpdates:=TJSONObject.ParseJSONValue(TEncoding.ANSI.GetString(BytesOf(ResponseContent.Memory,ResponseContent.Size)),False,True);

    AddRelease(JSONUpdates);

    Require(JSONUpdates.TryGetValue(PACKAGE_IDENTITY,JSONPackage),'unknown package "'+PACKAGE_IDENTITY+'"');
    Require(JSONPackage.TryGetValue('path',URIPackage),'package path is not defined');
    Require(JSONPackage.TryGetValue('version',FAvailableVersion),'unknown version');
    Require(JSONPackage.TryGetValue('timestamp',FAvailableDate),'unknown version date');

    FAvailableDescription:=JSONPackage.GetValue('description','');

  except on E: Exception do
    raise ENetHTTPException.Create('impossible to get updates: '+E.Message);
  end;

  ToLog('Available version: '+FAvailableVersion+' '+DateTimeToStr(UnixToDateTime(FAvailableDate,False)));

end;

procedure TUpdateCore.DownloadUpdatePackage;
begin

  var ResponseContent:=TMemoryStream.Create;

  AddRelease(ResponseContent);

  var Client:=THTTPClient.Create;

  AddRelease(Client);

  ToLog('Download package: '+URIPackage);

  try

    DownloadPackage:=TPath.Combine(FDownloadsPath,URIPackage.Substring(URIPackage.LastIndexOf('/')+1));

    if TFile.Exists(DownloadPackage) then
      Client.CustomHeaders['If-Modified-Since']:=ToGMTTime(TFile.GetLastWriteTime(DownloadPackage));

    var Response:=Client.Get(URIPackage,ResponseContent);

    case Response.StatusCode of
    304: {nothing} ;
    200: begin
         ResponseContent.SaveToFile(DownloadPackage);
         TFile.SetLastWriteTime(DownloadPackage,FromGMTTime(Response.HeaderValue['Expires'])); //? Expires Last-Modified
         end;
    else
      CheckResponse(Response);
    end;

  except on E: Exception do
    raise ENetHTTPException.Create('impossible to download update: '+E.Message);
  end;

end;

procedure TUpdateCore.DoReadUpdatesAsync;
begin

  FThread:=TThread.CreateAnonymousThread(procedure
  var Interval: Cardinal;
  begin

    repeat

      GetAvailableUpdates;

      var C:=CompareVersion(FAppVersion,FAvailableVersion);

      if C<0 then
      begin

        DownloadUpdatePackage;

        ToLog(Format('Update current version %s to %s',[FAppVersion,FAvailableVersion]));

        ToLog('Install package: '+DownloadPackage);

        if InstallPackage(DownloadPackage) then
          Halt
        else
          ToLog('Package not installed');

      end;

      Interval:=IfThen(C=0,CHECK_HIGH,CHECK_LOW);

      ToLog('Start check with interval: '+Interval.ToString+' ms');

    until FEvent.WaitFor(Interval)=wrSignaled;

  end);

  FThread.FreeOnTerminate:=False;
  FThread.OnTerminate:=OnReadUpdatesAsyncTerminate;
  FThread.Start;

end;

procedure TUpdateCore.OnReadUpdatesAsyncTerminate(Sender: TObject);
begin

  var E:=TThread(Sender).FatalException as Exception;

  if Assigned(E) then ToLog('Exception: '+E.Message);

end;

procedure TUpdateCore.StartUpdate;
begin

  if AppRunAsUpdater then
  begin
    UpdatePackage(ParamStr(2),ParamStr(3));
    Halt;
  end else
    DoReadUpdatesAsync;

end;

end.
