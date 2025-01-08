program uapp;

uses
  System.StartUpCopy,
  FMX.Forms,
  Update.Core,
  Unit1 in 'Forms\Unit1.pas' {Form1};

{$R *.res}

begin

  UpdateCore:=TUpdateCore.Create('https://raw.githubusercontent.com/slav-libx/update/refs/heads/main/updates.json');
  UpdateCore.StartUpdate;

  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;

  UpdateCore.Free;

end.
