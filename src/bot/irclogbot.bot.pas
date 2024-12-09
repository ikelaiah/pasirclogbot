unit IRCLogBot.Bot;

{$mode ObjFPC}{$H+}

interface

uses
  Classes
, SysUtils
, IdContext
, IdIRC
, IRCLogBot.Config
, IRCLogBot.Database
, IRCLogBot.Replay
;

type
{ TIRCLogBot }
  TIRCLogBot = class(TObject)
  private
    FIRC: TIdIRC;
    FJoinedChannel: Boolean;

    FConfig: TBotConfig;

    FDB: TDatabase;

    FReplay: TReplayThread;

    procedure OnConnected(Sender: TObject);
    procedure OnDisconnected(Sender: TObject);
    procedure OnNotice(ASender: TIdContext; const ANickname, AHost,
      ATarget, ANotice: String);
    procedure OnServerQuit(ASender: TIdContext; const ANickname, AHost,
      AServer, AReason: String);
    procedure OnJoin(ASender: TIdContext; const ANickname, AHost,
      AChannel: String);
    procedure OnPrivateMessage(ASender: TIdContext; const ANickname, AHost,
      ATarget, AMessage: String);

    procedure Help(const ATarget: String);
    procedure Replay(const ATarget: String; ACount: Integer);
  protected
  public
    constructor Create(const AConfig: TBotConfig);
    destructor Destroy; override;

    procedure Run;
    procedure Shutdown;
  published
  end;

implementation

uses
  IRCLogBot.Common
;


{ TIRCLogBot }

procedure TIRCLogBot.OnConnected(Sender: TObject);
begin
  debug('Connected to server.');
end;

procedure TIRCLogBot.OnDisconnected(Sender: TObject);
begin
  debug('Disconnected from server.');
end;

procedure TIRCLogBot.OnNotice(ASender: TIdContext; const ANickname, AHost,
  ATarget, ANotice: String);
begin
  debug('>> NOTICE: <%s:%s> (%s) "%s".', [
    ANickname,
    AHost,
    ATarget,
    ANotice
  ]);
end;

procedure TIRCLogBot.OnServerQuit(ASender: TIdContext; const ANickname, AHost,
  AServer, AReason: String);
begin
  debug('>> QUIT: <%s:%s> %s "%s".',[
    ANickname,
    AHost,
    AServer,
    AReason
  ]);
end;

procedure TIRCLogBot.OnJoin(ASender: TIdContext; const ANickname, AHost,
  AChannel: String);
begin
  debug('>> JOIN: <%s:%s> %s.', [
    ANickname,
    AHost,
    AChannel
  ]);
  if (ANickname = FConfig.NickName) and (AChannel = FConfig.Channel) then
  begin
    debug('Successfully joined my channel.');
    FJoinedChannel:= True;
    FIRC.Say(AChannel, 'I have arrived!!! TADAAAAA!!! Send me a private message with ".help" to see what I can do for you.');
  end;
end;

procedure TIRCLogBot.OnPrivateMessage(ASender: TIdContext; const ANickname,
  AHost, ATarget, AMessage: String);
var
  strings: TStringArray;
  count: Integer;
begin
  debug('>> PRIVMSG: <%s:%s>(%s) "%s".', [
    ANickname,
    AHost,
    ATarget,
    AMessage
  ]);
  if ATarget = FConfig.Channel then
  begin
    debug('Inserting: %s, %s, %s, %s.', [
      ANickname,
      AHost,
      ATarget,
      AMessage
    ]);
    FDB.Insert(ANickname, ATarget, AMessage);
    exit;
  end;
  if ATarget = FConfig.NickName then
  begin
    if Pos('.', AMessage) = 1 then
    begin
      // Parse commands
      if Pos('.help', Trim(AMessage)) = 1 then
      begin
        Help(ANickname);
        exit;
      end;
      if Pos('.replay', Trim(AMessage)) = 1 then
      begin
        strings:= AMessage.Split([' ']);
        //debug('Strings: %d', [Length(strings)]);
        try
          if Length(strings) > 1 then
          begin
            count:= StrToInt(strings[1]);
          end
          else
          begin
            count:= 10;
          end;
          //debug('Count: %d', [count]);
          Replay(ANickname, count);
        except
          on e:Exception do
          begin
            FIRC.Say(ANickname, 'Something went wrong: "' + e.Message + '". It''s been logged. Please contact the admin if I stop working.');
          end;
        end;
        exit;
      end;
    end
    else
    begin
      debug('No command.');
      FIRC.Say(ANickname, 'Not a command. Please use ".help" to see a list of commands.');
    end;
    exit;
  end;
end;

procedure TIRCLogBot.Help(const ATarget: String);
begin
  debug('Help command.');
  FIRC.Say(ATarget, 'Commands:');
  FIRC.Say(ATarget, '.help           - This help information.');
  FIRC.Say(ATarget, '.replay [count] - Raplays last <count> lines. Default is last 10 lines.');
end;

procedure TIRCLogBot.Replay(const ATarget: String; ACount: Integer);
var
  lines: TStringList;
begin
  debug('Replay command(%d).', [ACount]);
  lines:= FDB.Get(ACount);
  debug('Lines: %d.', [lines.Count]);
  FReplay.Add(ATarget, lines);
  lines.Free;
end;

procedure TIRCLogBot.Run;
begin
  try
    debug('Connecting...');
    FIRC.Connect;
  except
    on e:Exception do
    begin
      debug('Error connecting: "%s".', [e.Message]);
    end;
  end;
  try
    debug('Joining channel: "%s"...', [FConfig.Channel]);
    FIRC.Join(FConfig.Channel);
  except
    on e:Exception do
    begin
      debug('Error joining: "%s".', [e.Message]);
    end;
  end;
  debug('Starting Replay Thread.');
  FReplay:= TReplayThread.Create(FIRC);
end;

procedure TIRCLogBot.Shutdown;
begin
  debug('Terminating Replay Thread.');
  FReplay.Terminate;
  debug('Waiting for Replay Thread to terminate...');
  FReplay.WaitFor;
  if FIRC.Connected then
  begin
    debug('Disconnecting...');
    try
      if FJoinedChannel then FIRC.Say(FConfig.Channel, 'Boss sais I need to have a wee nap. See Y''All later...');
      FIRC.Disconnect('ZzZzZzZzZzZzZzZz...');
    except
      on e:Exception do
      begin
        debug('Error disconnecting: "%s".', [e.Message]);
      end;
    end;
  end;
end;

constructor TIRCLogBot.Create(const AConfig: TBotConfig);
begin
  FJoinedChannel:= False;

  // Config
  FConfig:= AConfig;

  // Setup IRC Client
  FIRC:= TIdIRC.Create;
  FIRC.Nickname:= FConfig.NickName;
  FIRC.Username:= FConfig.UserName;
  FIRC.RealName:= FConfig.RealName;
  FIRC.Host:= FConfig.Host;
  FIRC.Port:= FConfig.Port;
  FIRC.OnConnected:= @OnConnected;
  FIRC.OnDisconnected:= @OnDisconnected;
  FIRC.OnServerQuit:= @OnServerQuit;
  FIRC.OnJoin:= @OnJoin;
  FIRC.OnNotice:= @OnNotice;
  FIRC.OnPrivateMessage:= @OnPrivateMessage;

  // Setup Database
  try
    FDB:= TDatabase.Create(FConfig.Database);
  except
    on e:Exception do
    begin
      debug('Error creating db: "%s".', [e.Message]);
    end;
  end;
end;

destructor TIRCLogBot.Destroy;
begin
  FDB.Free;
  FIRC.Free;
  inherited Destroy;
end;

end.

