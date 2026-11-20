unit MicrosoftMcp.Tools.Calendar.Tests;

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  MCPServer.Tool.Base,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Fakes.GraphTransport,
  MicrosoftMcp.Fakes.UpstreamAccounts;

type
  [TestFixture]
  TCalendarToolsTests = class
  private
    FMailboxes: IMailboxRepository;
    FAccounts: TFakeUpstreamAccounts;
    FAccountsInterface: IInterface;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FServices: IToolServices;

    procedure AddMailbox(const Slug: string; const Kind: TMailboxKind; const Address: string);
    function Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
    function Confirm(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
    function CountRequests(const Method: string): Integer;
    function RequestBody(const Index: Integer): TJSONObject;
    function LastRequestBody: TJSONObject;
    procedure AssertNeedsConfirmation(const CallResult: TJSONObject);
    procedure AssertRanImmediately(const CallResult: TJSONObject);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure ListPassesRangeAsUtc;

    [Test]
    procedure TimesIgnoreTheLocaleTimeSeparator;

    [Test]
    procedure ListShowsEventsInUtc;

    [Test]
    procedure SearchFindsEventsBySubject;

    [Test]
    procedure GetReturnsAttendeesAndBody;

    [Test]
    procedure CreateWithoutAttendeesRunsImmediately;

    [Test]
    procedure CreateWithAttendeesNeedsConfirmation;

    [Test]
    procedure CreateConvertsOffsetToUtc;

    [Test]
    procedure CreateWithoutOffsetAssumesUtcAndSaysSo;

    [Test]
    procedure CreateWithTimeZoneKeepsLocalTime;

    [Test]
    procedure UpdateOfEventWithAttendeesNeedsConfirmation;

    [Test]
    procedure UpdateOfEventWithoutAttendeesRunsImmediately;

    [Test]
    procedure UpdateConfirmationReadsTheEventButNotAfterTheToken;

    [Test]
    procedure UpdateWithoutChangesIsRefused;

    [Test]
    procedure DeleteAlwaysNeedsConfirmation;

    [Test]
    procedure RespondWithoutSendingRunsImmediately;

    [Test]
    procedure RespondWithSendingNeedsConfirmation;

    [Test]
    procedure ProposeTimeNeedsConfirmation;

    [Test]
    procedure AvailabilityReturnsSlotsPerSchedule;

    [Test]
    procedure InvalidDateGivesClearError;

    [Test]
    procedure ToolsCarryTheirAnnotations;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  MCPAuth.Clock,
  MCPAuth.Secret.Token,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Store.Memory,
  MicrosoftMcp.Graph.ClientFactory,
  MicrosoftMcp.Confirm.Memory,
  MicrosoftMcp.Tools.Services,
  MicrosoftMcp.Tools.Calendar.List,
  MicrosoftMcp.Tools.Calendar.Search,
  MicrosoftMcp.Tools.Calendar.Get,
  MicrosoftMcp.Tools.Calendar.Create,
  MicrosoftMcp.Tools.Calendar.Update,
  MicrosoftMcp.Tools.Calendar.Delete,
  MicrosoftMcp.Tools.Calendar.Respond,
  MicrosoftMcp.Tools.Calendar.ProposeTime,
  MicrosoftMcp.Tools.Calendar.Availability,
  MicrosoftMcp.Tools.Calendar.Time,
  MicrosoftMcp.Tests.ToolCall;

const
  Kees = 'user-kees';
  WorkKey = 'acc-work';
  WorkUpn = 'kees@gdk.example.test';
  OwnSlug = 'gdk';
  SharedSlug = 'sales';
  SharedAddress = 'sales@gdk.example.test';
  PlanningStart = '{"dateTime":"2026-11-20T08:00:00.0000000","timeZone":"UTC"}';
  PlanningEnd = '{"dateTime":"2026-11-20T09:00:00.0000000","timeZone":"UTC"}';
  EventHead = '{"id":"e1","subject":"Planning","start":' + PlanningStart + ',"end":' + PlanningEnd + ',"location":{"displayName":"Room 1"},' +
              '"organizer":{"emailAddress":{"name":"Kees","address":"kees@gdk.example.test"}},"body":{"contentType":"html","content":"AGENDA TEXT"}';
  EventWithAttendees = EventHead + ',"attendees":[{"emailAddress":{"name":"Anna","address":"anna@other.example.test"},' +
                       '"status":{"response":"accepted"}}]}';
  EventWithoutAttendees = EventHead + ',"attendees":[]}';
  CreatedJson = '{"id":"new1","webLink":"https://calendar.example.test/new1"}';
  CreateWithoutAttendees = '{"mailbox":"gdk","subject":"Lunch","start":"2026-11-20T12:00:00+01:00","end":"2026-11-20T13:00:00+01:00"}';
  CreateWithAttendees = '{"mailbox":"gdk","subject":"Lunch","start":"2026-11-20T12:00:00+01:00","end":"2026-11-20T13:00:00+01:00",' +
                        '"attendees":["anna@other.example.test"]}';

{ TCalendarToolsTests }

procedure TCalendarToolsTests.Setup;
begin
  FMailboxes := TMailboxStoreMemory.Create;

  FAccounts := TFakeUpstreamAccounts.Create;
  FAccountsInterface := FAccounts;

  FTransport := TFakeGraphTransport.Create;
  FTransportInterface := FTransport;

  const Confirmations = TConfirmationsMemory.Create(TTokenGenerator.Create, TSystemClock.Create);
  FServices := TToolServices.Create(FMailboxes, FAccounts, TGraphClientFactory.Create(FTransport), Confirmations, 'https://auth.example.test/account');

  var Account := Default(TRemoteAccount);
  Account.Key         := WorkKey;
  Account.Provider    := 'microsoft';
  Account.UserName    := WorkUpn;
  Account.DisplayName := 'Kees (GDK)';
  FAccounts.AddAccount(Kees, Account, 'token-work');

  AddMailbox(OwnSlug, TMailboxKind.Own, '');
  AddMailbox(SharedSlug, TMailboxKind.Shared, SharedAddress);
end;

procedure TCalendarToolsTests.TearDown;
begin
  FServices := nil;
  FTransport := nil;
  FTransportInterface := nil;
  FAccounts := nil;
  FAccountsInterface := nil;
  FMailboxes := nil;
end;

procedure TCalendarToolsTests.AddMailbox(const Slug: string; const Kind: TMailboxKind; const Address: string);
begin
  var Mailbox := Default(TMailbox);
  Mailbox.UserId      := Kees;
  Mailbox.Slug        := Slug;
  Mailbox.DisplayName := Slug;
  Mailbox.Address     := Address;
  Mailbox.AccountKey  := WorkKey;
  Mailbox.Kind        := Kind;

  FMailboxes.Save(Mailbox);
end;

function TCalendarToolsTests.Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
begin
  Result := TToolCall.Run(Tool, Kees, ArgumentsJson);
end;

// Calls a confirmed tool twice, as Claude does, and returns the answer of the second call.
function TCalendarToolsTests.Confirm(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
begin
  const FirstAnswer = Call(Tool, ArgumentsJson);
  try
    const Token = TToolCall.Structured(FirstAnswer).GetValue<string>('confirmation_token');
    const WithToken = ArgumentsJson.TrimRight(['}']) + Format(',"confirmation_token":"%s"}', [Token]);

    Result := Call(Tool, WithToken);
  finally
    FirstAnswer.Free;
  end;
end;

function TCalendarToolsTests.CountRequests(const Method: string): Integer;
begin
  Result := 0;
  for var Index := 0 to FTransport.RequestCount - 1 do
  begin
    if FTransport.RequestAt(Index).Method = Method then
      Inc(Result);
  end;
end;

function TCalendarToolsTests.RequestBody(const Index: Integer): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(FTransport.RequestAt(Index).Body) as TJSONObject;
end;

function TCalendarToolsTests.LastRequestBody: TJSONObject;
begin
  Result := RequestBody(FTransport.RequestCount - 1);
end;

procedure TCalendarToolsTests.AssertNeedsConfirmation(const CallResult: TJSONObject);
begin
  Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
  Assert.IsTrue(TToolCall.Structured(CallResult).GetValue<Boolean>('confirmation_required'), CallResult.ToJSON);
  Assert.IsNotEmpty(TToolCall.Structured(CallResult).GetValue<string>('confirmation_token'));
end;

procedure TCalendarToolsTests.AssertRanImmediately(const CallResult: TJSONObject);
begin
  Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
  Assert.IsNull(TToolCall.Structured(CallResult).GetValue('confirmation_required'), 'The tool asked for a confirmation');
end;

procedure TCalendarToolsTests.ListPassesRangeAsUtc;
begin
  FTransport.Respond(200, '{"value":[]}');
  const Tool: IMCPTool = TCalendarListTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","start":"2026-11-20T09:00:00+01:00","end":"2026-11-20T18:00:00+01:00","top":10}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Request = FTransport.LastRequest;
    Assert.Contains(Request.Url, '/me/calendarView');
    Assert.Contains(Request.Url, 'startDateTime=2026-11-20T08%3A00%3A00');
    Assert.Contains(Request.Url, 'endDateTime=2026-11-20T17%3A00%3A00');
    Assert.Contains(Request.Url, 'top=10');

    var AskedForUtc := False;
    for var Header in Request.Headers do
    begin
      AskedForUtc := AskedForUtc or Header.Value.Contains('outlook.timezone="UTC"');
    end;
    Assert.IsTrue(AskedForUtc, 'The request must ask Graph for UTC times');
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.ListShowsEventsInUtc;
begin
  FTransport.Respond(200, '{"value":[' + EventWithAttendees + ']}');
  const Tool: IMCPTool = TCalendarListTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","start":"2026-11-20T00:00:00Z","end":"2026-11-21T00:00:00Z"}');
  try
    const Answer = TToolCall.Structured(CallResult);
    Assert.AreEqual('Planning', Answer.GetValue<string>('events[0].subject'));
    Assert.AreEqual('2026-11-20T08:00:00Z', Answer.GetValue<string>('events[0].start'));
    Assert.AreEqual('2026-11-20T09:00:00Z', Answer.GetValue<string>('events[0].end'));
    Assert.AreEqual('anna@other.example.test', Answer.GetValue<string>('events[0].attendees[0].email'));
    Assert.AreEqual('', Answer.GetValue<string>('note'));
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.SearchFindsEventsBySubject;
begin
  FTransport.Respond(200, '{"value":[' + EventWithAttendees + ']}');
  const Tool: IMCPTool = TCalendarSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"sales","query":"planning"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('e1', TToolCall.Structured(CallResult).GetValue<string>('events[0].id'));
    Assert.Contains(FTransport.LastRequest.Url, '/users/sales');
    Assert.Contains(FTransport.LastRequest.Url, '/calendarView');
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.GetReturnsAttendeesAndBody;
begin
  FTransport.Respond(200, EventWithAttendees);
  const Tool: IMCPTool = TCalendarGetTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","event_id":"e1"}');
  try
    const Answer = TToolCall.Structured(CallResult);
    Assert.AreEqual('Room 1', Answer.GetValue<string>('event.location'));
    Assert.AreEqual('accepted', Answer.GetValue<string>('event.attendees[0].response'));
    Assert.AreEqual('AGENDA TEXT', Answer.GetValue<string>('body'));
    Assert.Contains(FTransport.LastRequest.Url, '/me/events/e1');
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.CreateWithoutAttendeesRunsImmediately;
begin
  FTransport.Respond(201, CreatedJson);
  const Tool: IMCPTool = TCalendarCreateTool.Create(FServices);

  const CallResult = Call(Tool, CreateWithoutAttendees);
  try
    AssertRanImmediately(CallResult);
    Assert.AreEqual('created', TToolCall.Structured(CallResult).GetValue<string>('status'));
    Assert.AreEqual('new1', TToolCall.Structured(CallResult).GetValue<string>('event_id'));
    Assert.AreEqual('POST', FTransport.LastRequest.Method);
    Assert.Contains(FTransport.LastRequest.Url, '/me/events');
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.CreateWithAttendeesNeedsConfirmation;
begin
  FTransport.Respond(201, CreatedJson);
  const Tool: IMCPTool = TCalendarCreateTool.Create(FServices);

  const FirstAnswer = Call(Tool, CreateWithAttendees);
  try
    AssertNeedsConfirmation(FirstAnswer);
    Assert.AreEqual(0, FTransport.RequestCount, 'Nothing may reach Graph before the confirmation');

    const Summary = TToolCall.Structured(FirstAnswer).GetValue<string>('summary');
    Assert.Contains(Summary, '"gdk" (kees@gdk.example.test)');
    Assert.Contains(Summary, 'Lunch');
    Assert.Contains(Summary, '2026-11-20T11:00:00Z to 2026-11-20T12:00:00Z');
    Assert.Contains(Summary, 'anna@other.example.test');
  finally
    FirstAnswer.Free;
  end;

  const SecondAnswer = Confirm(Tool, CreateWithAttendees);
  try
    Assert.AreEqual('created', TToolCall.Structured(SecondAnswer).GetValue<string>('status'));
    Assert.AreEqual(1, CountRequests('POST'));

    const Body = LastRequestBody;
    try
      Assert.AreEqual('anna@other.example.test', Body.GetValue<string>('attendees[0].emailAddress.address'));
    finally
      Body.Free;
    end;
  finally
    SecondAnswer.Free;
  end;
end;

procedure TCalendarToolsTests.CreateConvertsOffsetToUtc;
begin
  FTransport.Respond(201, CreatedJson);
  const Tool: IMCPTool = TCalendarCreateTool.Create(FServices);

  const CallResult = Call(Tool, CreateWithoutAttendees);
  try
    const Body = LastRequestBody;
    try
      Assert.AreEqual('2026-11-20T11:00:00', Body.GetValue<string>('start.dateTime'));
      Assert.AreEqual('UTC', Body.GetValue<string>('start.timeZone'));
      Assert.AreEqual('2026-11-20T12:00:00', Body.GetValue<string>('end.dateTime'));
    finally
      Body.Free;
    end;

    Assert.AreEqual('', TToolCall.Structured(CallResult).GetValue<string>('note'));
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.CreateWithoutOffsetAssumesUtcAndSaysSo;
begin
  FTransport.Respond(201, CreatedJson);
  const Tool: IMCPTool = TCalendarCreateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","subject":"Lunch","start":"2026-11-20T12:00:00","end":"2026-11-20T13:00:00"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(TToolCall.Structured(CallResult).GetValue<string>('note'), 'UTC');

    const Body = LastRequestBody;
    try
      Assert.AreEqual('2026-11-20T12:00:00', Body.GetValue<string>('start.dateTime'));
      Assert.AreEqual('UTC', Body.GetValue<string>('start.timeZone'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.CreateWithTimeZoneKeepsLocalTime;
begin
  FTransport.Respond(201, CreatedJson);
  const Tool: IMCPTool = TCalendarCreateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","subject":"Lunch","start":"2026-11-20T12:00:00","end":"2026-11-20T13:00:00","time_zone":"Europe/Amsterdam"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('', TToolCall.Structured(CallResult).GetValue<string>('note'));

    const Body = LastRequestBody;
    try
      Assert.AreEqual('2026-11-20T12:00:00', Body.GetValue<string>('start.dateTime'));
      Assert.AreEqual('Europe/Amsterdam', Body.GetValue<string>('start.timeZone'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.UpdateOfEventWithAttendeesNeedsConfirmation;
begin
  FTransport.Respond(200, EventWithAttendees);
  const Tool: IMCPTool = TCalendarUpdateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","event_id":"e1","subject":"Replanning"}');
  try
    AssertNeedsConfirmation(CallResult);
    Assert.AreEqual(0, CountRequests('PATCH'));

    const Summary = TToolCall.Structured(CallResult).GetValue<string>('summary');
    Assert.Contains(Summary, '"Planning" (2026-11-20T08:00:00Z to 2026-11-20T09:00:00Z)');
    Assert.Contains(Summary, 'Anna <anna@other.example.test>');
    Assert.Contains(Summary, 'subject becomes "Replanning"');
    Assert.Contains(Summary, '"gdk" (kees@gdk.example.test)');
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.UpdateOfEventWithoutAttendeesRunsImmediately;
begin
  FTransport.Respond(200, EventWithoutAttendees);
  const Tool: IMCPTool = TCalendarUpdateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","event_id":"e1","subject":"Replanning"}');
  try
    AssertRanImmediately(CallResult);
    Assert.AreEqual('updated', TToolCall.Structured(CallResult).GetValue<string>('status'));
    Assert.AreEqual(1, CountRequests('PATCH'));

    const Body = LastRequestBody;
    try
      Assert.AreEqual('Replanning', Body.GetValue<string>('subject'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.UpdateConfirmationReadsTheEventButNotAfterTheToken;
begin
  FTransport.Respond(200, EventWithAttendees);
  const Tool: IMCPTool = TCalendarUpdateTool.Create(FServices);

  const CallResult = Confirm(Tool, '{"mailbox":"gdk","event_id":"e1","location":"Room 2"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('updated', TToolCall.Structured(CallResult).GetValue<string>('status'));

    // First call: one read to decide, one for the summary. The call with the token goes straight to the change.
    Assert.AreEqual(2, CountRequests('GET'));
    Assert.AreEqual(1, CountRequests('PATCH'));
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.UpdateWithoutChangesIsRefused;
begin
  FTransport.Respond(200, EventWithoutAttendees);
  const Tool: IMCPTool = TCalendarUpdateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","event_id":"e1"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'at least one field');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.DeleteAlwaysNeedsConfirmation;
begin
  FTransport.Respond(200, EventWithoutAttendees);
  const Tool: IMCPTool = TCalendarDeleteTool.Create(FServices);

  const FirstAnswer = Call(Tool, '{"mailbox":"gdk","event_id":"e1"}');
  try
    AssertNeedsConfirmation(FirstAnswer);
    Assert.AreEqual(0, CountRequests('DELETE'));
    Assert.Contains(TToolCall.Structured(FirstAnswer).GetValue<string>('summary'), 'Planning');
  finally
    FirstAnswer.Free;
  end;

  const SecondAnswer = Confirm(Tool, '{"mailbox":"gdk","event_id":"e1"}');
  try
    Assert.AreEqual('deleted', TToolCall.Structured(SecondAnswer).GetValue<string>('status'));
    Assert.AreEqual(1, CountRequests('DELETE'));
    Assert.Contains(FTransport.LastRequest.Url, '/me/events/e1');
  finally
    SecondAnswer.Free;
  end;
end;

procedure TCalendarToolsTests.RespondWithoutSendingRunsImmediately;
begin
  FTransport.Respond(202, '');
  const Tool: IMCPTool = TCalendarRespondTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","event_id":"e1","response":"accept","comment":"See you","send_response":false}');
  try
    AssertRanImmediately(CallResult);
    Assert.AreEqual(1, FTransport.RequestCount);
    Assert.AreEqual('POST', FTransport.LastRequest.Method);
    Assert.Contains(FTransport.LastRequest.Url, '/me/events/e1/accept');

    const Body = LastRequestBody;
    try
      Assert.IsFalse(Body.GetValue<Boolean>('sendResponse'));
      Assert.AreEqual('See you', Body.GetValue<string>('comment'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.RespondWithSendingNeedsConfirmation;
begin
  FTransport.Respond(200, EventWithAttendees);
  const Tool: IMCPTool = TCalendarRespondTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","event_id":"e1","response":"decline"}');
  try
    AssertNeedsConfirmation(CallResult);
    Assert.Contains(TToolCall.Structured(CallResult).GetValue<string>('summary'), 'Decline');
    Assert.AreEqual(0, CountRequests('POST'));
  finally
    CallResult.Free;
  end;

  const Sent = Confirm(Tool, '{"mailbox":"gdk","event_id":"e1","response":"decline"}');
  try
    Assert.Contains(FTransport.LastRequest.Url, '/me/events/e1/decline');
  finally
    Sent.Free;
  end;
end;

procedure TCalendarToolsTests.ProposeTimeNeedsConfirmation;
begin
  FTransport.Respond(200, EventWithAttendees);
  const Tool: IMCPTool = TCalendarProposeTimeTool.Create(FServices);
  const Arguments = '{"mailbox":"gdk","event_id":"e1","start":"2026-11-21T10:00:00Z","end":"2026-11-21T11:00:00Z","comment":"Busy then"}';

  const FirstAnswer = Call(Tool, Arguments);
  try
    AssertNeedsConfirmation(FirstAnswer);
    Assert.Contains(TToolCall.Structured(FirstAnswer).GetValue<string>('summary'), '2026-11-21T10:00:00Z to 2026-11-21T11:00:00Z');
    Assert.AreEqual(0, CountRequests('POST'));
  finally
    FirstAnswer.Free;
  end;

  const SecondAnswer = Confirm(Tool, Arguments);
  try
    Assert.AreEqual(1, CountRequests('POST'));

    const Body = LastRequestBody;
    try
      Assert.AreEqual('2026-11-21T10:00:00', Body.GetValue<string>('proposedNewTime.start.dateTime'));
      Assert.AreEqual('UTC', Body.GetValue<string>('proposedNewTime.start.timeZone'));
    finally
      Body.Free;
    end;
  finally
    SecondAnswer.Free;
  end;
end;

procedure TCalendarToolsTests.AvailabilityReturnsSlotsPerSchedule;
begin
  FTransport.Respond(200, '{"value":[{"scheduleId":"anna@other.example.test","availabilityView":"0220",' +
                          '"scheduleItems":[{"status":"busy","subject":"Planning","start":{"dateTime":"2026-11-20T08:30:00.0000000","timeZone":"UTC"},' +
                          '"end":{"dateTime":"2026-11-20T09:30:00.0000000","timeZone":"UTC"}}]},' +
                          '{"scheduleId":"room@other.example.test","availabilityView":"0000","scheduleItems":[]}]}');
  const Tool: IMCPTool = TCalendarAvailabilityTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","schedules":["anna@other.example.test","room@other.example.test"],' +
                                '"start":"2026-11-20T09:00:00+01:00","end":"2026-11-20T11:00:00+01:00","interval_minutes":30}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Answer = TToolCall.Structured(CallResult);
    Assert.AreEqual('anna@other.example.test', Answer.GetValue<string>('schedules[0].schedule'));
    Assert.AreEqual('0220', Answer.GetValue<string>('schedules[0].availability_view'));
    Assert.AreEqual('free', Answer.GetValue<string>('schedules[0].slots[0].status'));
    Assert.AreEqual('busy', Answer.GetValue<string>('schedules[0].slots[1].status'));
    Assert.AreEqual('2026-11-20T08:30:00Z', Answer.GetValue<string>('schedules[0].slots[1].start'));
    Assert.AreEqual('2026-11-20T09:00:00Z', Answer.GetValue<string>('schedules[0].slots[1].end'));
    Assert.AreEqual('Planning', Answer.GetValue<string>('schedules[0].items[0].subject'));
    Assert.AreEqual('room@other.example.test', Answer.GetValue<string>('schedules[1].schedule'));

    Assert.Contains(FTransport.LastRequest.Url, '/me/calendar/getSchedule');
    const Body = LastRequestBody;
    try
      Assert.AreEqual(30, Body.GetValue<Integer>('availabilityViewInterval'));
      Assert.AreEqual('2026-11-20T08:00:00', Body.GetValue<string>('startTime.dateTime'));
      Assert.AreEqual('UTC', Body.GetValue<string>('startTime.timeZone'));
      Assert.AreEqual('room@other.example.test', Body.GetValue<string>('schedules[1]'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TCalendarToolsTests.InvalidDateGivesClearError;
begin
  const Tool: IMCPTool = TCalendarCreateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","subject":"Lunch","start":"tomorrow noon","end":"2026-11-20T13:00:00Z"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));

    const Text = TToolCall.Text(CallResult);
    Assert.Contains(Text, '"start"');
    Assert.Contains(Text, 'ISO 8601');
    Assert.Contains(Text, 'tomorrow noon');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;

  const EndBeforeStart = Call(Tool, '{"mailbox":"gdk","subject":"Lunch","start":"2026-11-20T13:00:00Z","end":"2026-11-20T12:00:00Z"}');
  try
    Assert.IsTrue(TToolCall.IsError(EndBeforeStart));
    Assert.Contains(TToolCall.Text(EndBeforeStart), '"end"');
  finally
    EndBeforeStart.Free;
  end;
end;

procedure TCalendarToolsTests.ToolsCarryTheirAnnotations;
begin
  const List = TCalendarListTool.Create(FServices);
  const ListTool: IMCPTool = List;
  Assert.IsTrue(List.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.AreEqual('calendar_list', ListTool.Name);

  const Delete = TCalendarDeleteTool.Create(FServices);
  const DeleteTool: IMCPTool = Delete;
  Assert.IsFalse(Delete.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.IsTrue(Delete.GetAnnotations.GetValue<Boolean>('destructiveHint'));
  Assert.IsTrue(Delete.GetAnnotations.GetValue<Boolean>('openWorldHint'));
  Assert.IsNull(DeleteTool.OutputSchema);
  Assert.AreEqual('calendar_delete', DeleteTool.Name);

  const Availability = TCalendarAvailabilityTool.Create(FServices);
  const AvailabilityTool: IMCPTool = Availability;
  Assert.IsTrue(Availability.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.AreEqual('calendar_availability', AvailabilityTool.Name);
end;

procedure TCalendarToolsTests.TimesIgnoreTheLocaleTimeSeparator;
begin
  const Moment = EncodeDateTime(2026, 11, 20, 9, 30, 15, 0);
  const SavedSeparator = FormatSettings.TimeSeparator;
  FormatSettings.TimeSeparator := '.';
  try
    Assert.AreEqual('2026-11-20T09:30:15Z', TCalendarTime.ToIso(Moment));
    Assert.AreEqual('2026-11-20T09:30:15', TCalendarTime.ToGraph(Moment));
  finally
    FormatSettings.TimeSeparator := SavedSeparator;
  end;
end;

end.
