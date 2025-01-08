program cuapp;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  Update.Core;

begin

  try

    UpdateCore:=TUpdateCore.Create('https://raw.githubusercontent.com/slav-libx/update/refs/heads/main/updates.json');
    UpdateCore.StartUpdate;

    Writeln(UpdateCore.AppVersion);

    while True do CheckSynchronize(100);

    UpdateCore.Free;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

end.
