unit MicrosoftMcp.Tools.Calendar.Types;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Calendar.Types,
  MicrosoftMcp.Tools.Base;

type
  TCalendarAttendeeItem = record
    Name: string;
    Email: string;
    Response: string;
  end;

  // An event as the tools show it: times in ISO 8601 UTC.
  TCalendarEventItem = record
    Id: string;
    Subject: string;
    Start: string;

    [SchemaName('end')]
    Finish: string;

    Location: string;
    Organizer: string;
    Attendees: TArray<TCalendarAttendeeItem>;

    [SchemaName('is_all_day')]
    IsAllDay: Boolean;

    [SchemaName('is_cancelled')]
    IsCancelled: Boolean;

    [SchemaName('is_online_meeting')]
    IsOnlineMeeting: Boolean;

    [SchemaName('online_meeting_url')]
    OnlineMeetingUrl: string;

    [SchemaName('web_link')]
    WebLink: string;

    [SchemaName('body_preview')]
    BodyPreview: string;

    [SchemaName('show_as')]
    ShowAs: string;

    class function FromEvent(const Event: TCalendarEvent): TCalendarEventItem; static;
  end;

  TCalendarListResponse = class
  private
    FEvents: TArray<TCalendarEventItem>;
    FHasMore: Boolean;
    FNote: string;

  public
    property Events: TArray<TCalendarEventItem> read FEvents write FEvents;

    [SchemaName('has_more')]
    property HasMore: Boolean read FHasMore write FHasMore;

    [SchemaDescription('Remarks about how the times were read; empty when there is nothing to remark')]
    property Note: string read FNote write FNote;

    class function From(const Events: TArray<TCalendarEvent>; const HasMore: Boolean; const Note: string): TCalendarListResponse; static;
  end;

  TCalendarEventResponse = class
  private
    FEvent: TCalendarEventItem;
    FBody: string;

  public
    property Event: TCalendarEventItem read FEvent write FEvent;

    [SchemaDescription('Body of the event as Graph returns it, usually HTML')]
    property Body: string read FBody write FBody;

    class function From(const Event: TCalendarEvent): TCalendarEventResponse; static;
  end;

  TCalendarActionResponse = class
  private
    FStatus: string;
    FEventId: string;
    FWebLink: string;
    FOnlineMeetingUrl: string;
    FNote: string;

  public
    property Status: string read FStatus write FStatus;

    [SchemaName('event_id')]
    property EventId: string read FEventId write FEventId;

    [SchemaName('web_link')]
    property WebLink: string read FWebLink write FWebLink;

    [SchemaName('online_meeting_url')]
    property OnlineMeetingUrl: string read FOnlineMeetingUrl write FOnlineMeetingUrl;

    [SchemaDescription('Remarks about how the times were read; empty when there is nothing to remark')]
    property Note: string read FNote write FNote;

    class function Done(const Status, Note: string): TCalendarActionResponse; static;
    class function From(const Status: string; const EventResult: TCreateEventResult; const Note: string): TCalendarActionResponse; static;
  end;

  // Parameters of the tools that act on one event.
  TEventParams = class(TMicrosoftToolParams)
  private
    FEventId: string;

  public
    [SchemaName('event_id')]
    [SchemaDescription('Id of the event, from calendar_list or calendar_search')]
    property EventId: string read FEventId write FEventId;
  end;

  // The same for the tools that need a confirmation.
  TConfirmedEventParams = class(TConfirmableToolParams)
  private
    FEventId: string;

  public
    [SchemaName('event_id')]
    [SchemaDescription('Id of the event, from calendar_list or calendar_search')]
    property EventId: string read FEventId write FEventId;
  end;

implementation

uses
  MicrosoftMcp.Tools.Calendar.Time;

{ TCalendarEventItem }

class function TCalendarEventItem.FromEvent(const Event: TCalendarEvent): TCalendarEventItem;
begin
  Result := Default(TCalendarEventItem);
  Result.Id               := Event.Id;
  Result.Subject          := Event.Subject;
  Result.Start            := TCalendarTime.FromGraph(Event.StartDateTime);
  Result.Finish           := TCalendarTime.FromGraph(Event.EndDateTime);
  Result.Location         := Event.Location;
  Result.Organizer        := Event.Organizer;
  Result.IsAllDay         := Event.IsAllDay;
  Result.IsCancelled      := Event.IsCancelled;
  Result.IsOnlineMeeting  := Event.IsOnlineMeeting;
  Result.OnlineMeetingUrl := Event.OnlineMeetingUrl;
  Result.WebLink          := Event.WebLink;
  Result.BodyPreview      := Event.BodyPreview;
  Result.ShowAs           := Event.ShowAs;

  Result.Attendees := [];
  for var Attendee in Event.Attendees do
  begin
    var Item := Default(TCalendarAttendeeItem);
    Item.Name     := Attendee.Name;
    Item.Email    := Attendee.Email;
    Item.Response := Attendee.Response;
    Result.Attendees := Result.Attendees + [Item];
  end;
end;

{ TCalendarListResponse }

class function TCalendarListResponse.From(const Events: TArray<TCalendarEvent>; const HasMore: Boolean; const Note: string): TCalendarListResponse;
begin
  Result := TCalendarListResponse.Create;

  var Items: TArray<TCalendarEventItem> := [];
  for var Event in Events do
  begin
    Items := Items + [TCalendarEventItem.FromEvent(Event)];
  end;

  Result.Events := Items;
  Result.HasMore := HasMore;
  Result.Note := Note;
end;

{ TCalendarEventResponse }

class function TCalendarEventResponse.From(const Event: TCalendarEvent): TCalendarEventResponse;
begin
  Result := TCalendarEventResponse.Create;
  Result.Event := TCalendarEventItem.FromEvent(Event);
  Result.Body := Event.Body;
end;

{ TCalendarActionResponse }

class function TCalendarActionResponse.Done(const Status, Note: string): TCalendarActionResponse;
begin
  Result := TCalendarActionResponse.Create;
  Result.Status := Status;
  Result.Note := Note;
end;

class function TCalendarActionResponse.From(const Status: string; const EventResult: TCreateEventResult; const Note: string): TCalendarActionResponse;
begin
  Result := Done(Status, Note);
  Result.EventId := EventResult.Id;
  Result.WebLink := EventResult.WebLink;
  Result.OnlineMeetingUrl := EventResult.OnlineMeetingUrl;
end;

end.
