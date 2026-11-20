unit MicrosoftMcp.Tools.Calendar.Support;

interface

uses
  MSGraph.Graph.Http,
  MSGraph.Graph.Calendar.Types,
  MSGraph.Graph.Calendar.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces;

type
  // Helpers the calendar tools share: the Microsoft365-4D client and the texts of the confirmation summaries.
  TCalendarSupport = class
  public
    class function Client(const Graph: TGraphHttpClient): ICalendarClient; static;

    // For the summaries of confirmed tools: reads the event the confirmation is about.
    class function LoadEvent(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const EventId: string): TCalendarEvent; static;

    class function CleanAttendees(const Attendees: TArray<string>): TArray<string>; static;
    class function AttendeesText(const Attendees: TArray<TAttendee>): string; static;
    class function EventText(const Event: TCalendarEvent): string; static;
  end;

implementation

uses
  System.SysUtils,
  MSGraph.Graph.Calendar,
  MicrosoftMcp.Tools.Calendar.Time;

resourcestring
  EventFormat = '"%s" (%s to %s)';
  NoAttendeesText = '(no attendees)';
  AttendeeFormat = '%s <%s>';

{ TCalendarSupport }

class function TCalendarSupport.Client(const Graph: TGraphHttpClient): ICalendarClient;
begin
  Result := TCalendarClient.Create(Graph, False);
end;

class function TCalendarSupport.LoadEvent(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const EventId: string): TCalendarEvent;
begin
  const Graph = GraphClients.Create(Mailbox);
  try
    Result := Client(Graph).GetEvent(EventId);
  finally
    Graph.Free;
  end;
end;

class function TCalendarSupport.CleanAttendees(const Attendees: TArray<string>): TArray<string>;
begin
  Result := [];
  for var Attendee in Attendees do
  begin
    const Trimmed = Attendee.Trim;
    if not Trimmed.IsEmpty then
      Result := Result + [Trimmed];
  end;
end;

class function TCalendarSupport.AttendeesText(const Attendees: TArray<TAttendee>): string;
begin
  var Names: TArray<string> := [];
  for var Attendee in Attendees do
  begin
    const HasName = ((not Attendee.Name.IsEmpty) and (not SameText(Attendee.Name, Attendee.Email)));
    if HasName then
      Names := Names + [Format(AttendeeFormat, [Attendee.Name, Attendee.Email])]
    else
      Names := Names + [Attendee.Email];
  end;

  Result := string.Join(', ', Names);
  if Result.IsEmpty then
    Result := NoAttendeesText;
end;

class function TCalendarSupport.EventText(const Event: TCalendarEvent): string;
begin
  Result := Format(EventFormat, [Event.Subject, TCalendarTime.FromGraph(Event.StartDateTime), TCalendarTime.FromGraph(Event.EndDateTime)]);
end;

end.
