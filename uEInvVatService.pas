unit uEInvVatService;

interface

uses
  Classes, SysUtils, ComObj, Generics.Collections,
  Variants, Dialogs, UITypes, uVars;

const
  // перечень статусов, должен полностью соответсвовать справочнику в БД
  TInvoiceStatus: array[0..8] of string = (
        // 0 - без статуса (такого статуса на портале нет, добавлен для системы)
        'NULL',
        // 1 - В разработке
        'IN_PROGRESS', 
        // 2 - В разработке. Ошибка
        'IN_PROGRESS_ERROR' ,
        // 3 - Выставлен
        'COMPLETED', 
        // 4 - Выставлен. Подписан получателем
        'COMPLETED_SIGNED',
        // 5 - Выставлен. Аннулирован поставщиком
        'ON_AGREEMENT_CANCEL', 
        // 6 - На согласовании
        'ON_AGREEMENT',
        // 7 - Аннулирован
        'CANCELLED',
        // 8 - Ошибка портала
        'PORTAL_ERROR' );
  TCaprionStatus: array[0..8] of string = (
        '<нет>',
        'В разработке',
        'В разработке. Ошибка',
        'Выставлен',
        'Выставлен. Подписан получателем',
        'Выставлен. Аннулирован поставщиком',
        'На согласовании',
        'Аннулирован',
        'Ошибка портала' );
        

type
  //класс с результатами отправки ЭСЧФ
  TSendInfo = class
  public
   VatInvoice: string;  //номер ЭСЧФ
   IsException: Boolean;//наличие ошибки (да/нет)
   ResMessage: string;  //сообщение с результатом
   Status: integer;     //статус ЭСЧФ с портала (по умолчанию 0)
   constructor Create(vatInv: string; isExc: Boolean; resMsg:string; stat: Integer = 0);
  end;

  //класс взаимодействия с порталом
  TEInvVatService = class(TThread)
  private
    //переменные для компоненты доступа к порталу ЭСФЧ
    EVatService: Variant;      //сам компонент ActiveX
    EVatAU: Integer;           //признак подключения (0 - нет, 1 - да)
    files_path: string;        //путь к хранилищу файлов xml (устанавливается при создании объекта)         
    procedure Disconnect;      //отключение от портала
    procedure Login;           //авторизация пользователя
    function Connect: Boolean; //подключение к порталу
    function ExceptionMessage(msg: string): string; //string + дополненительное сообщение от портала
    function GetStatusInt(s: string): Integer;  //преобразование статуса string в integer
    procedure AddLog(msg:string);
  public
    Progress: integer;
    FOperation: TVatOperation;
    FStatus: TSyncFilesStatus;
    invoices: TList<string>;
    sendinfo: TList<TSendInfo>;
    //создание объекта для начала работы
    constructor Create(file_path: string);

    //уничтожение объекта для завершения работы
    destructor Destroy; override;

    //отправка файла на портал
    //обрабатывается список invoices c номерами ЭСЧФ (наименованием файла без его типа .xml)
    //выполняется загрузка из файлов.
    //Важно!!! в основном каталоге по пути file_path должен быть каталог xsd с шаблонами
    procedure SignAndSendOut;

    //проверка статуса ЭСЧФ на портале
    //обрабатывается список invoices c номерами ЭСЧФ
    procedure CheckStatus;
    function Stop: boolean;
   protected
    procedure SyncThr;
    procedure Execute; override;
    procedure DoTerminate; override;
  end;

const
  //адрес портала для взаимодействия
  portalUrl  = 'https://195.50.4.43/InvoicesWS/services/InvoicesPort' ;       //тестовый
//portalUrl = 'https://ws.vat.gov.by:443/InvoicesWS/services/InvoicesPort?wsdl';

var  
  resMsg: string;
                     
implementation

uses uEInvVatServiceLoad, uMain;    


constructor TSendInfo.Create(vatInv: string; isExc: Boolean; resMsg: string; stat: integer = 0);
begin
  VatInvoice := vatInv;
  IsException := isExc;
  ResMessage := resMsg;
  Status := stat;
end;


//инициализация объекта основного модуля взаимодействия и подключение необходимого компонента ActiveX
constructor TEInvVatService.Create(file_path: string);
var
  connector: string;
begin
  inherited Create(True);
  files_path := file_path;
  FStatus := thStopped;
  Progress := 0;
  EVatAU := 0;
  invoices:= TList<string>.Create;
  sendinfo:= TList<TSendInfo>.Create;   
  try
    connector := 'EInvVatService.Connector';
    try
      EVatService := GetActiveOleObject(connector);
    except
      EVatService := CreateOleObject(connector);
    end;
    AddLog('Компоненты доступа к порталу ЭСФЧ загружены');
  except
    AddLog('На компьютере не обнаружены компоненты, необходимые для доступа к порталу ЭСФЧ!');
    FStatus := thLocked;
  //  Destroy;
  end;
end;

//уничтожение объекта для завершения работы
destructor TEInvVatService.Destroy;
begin     
  Disconnect;
  FreeAndNil(invoices);
  FreeAndNil(sendinfo);
  inherited;
end;

//авторизация пользователя
procedure TEInvVatService.Login;
var
  s: string;
begin   
  if EVatService.Login[s, 0] = 0 then
  begin
    EVatAU := 1;
    AddLog('Авторизация успешна');  
  end
  else
  begin
    EVatAU := 0;
    AddLog(ExceptionMessage('Ошибка авторизации'));  
    Abort;
  end;     
end;


//подключение к порталу, на выходе результат подключения
function TEInvVatService.Connect: Boolean;
begin
  Result:=False;
  if EVatAU = 0 then
    Login;
  if EVatService.Connect[portalUrl] = 0 then
    Result:=True
  else
    AddLog(ExceptionMessage('Ошибка подключения'));
end;

//отключение от портала
procedure TEInvVatService.Disconnect;
begin
  if EVatAU = 1 then
  begin
    if EVatService.Disconnect <> 0 then
      AddLog('Ошибка при завершении подключения к службе регистрации');
    if EVatService.Logout <> 0 then
      AddLog('Ошибка при завершении авторизованной сессии');
  end;
end;


procedure TEInvVatService.DoTerminate;
begin
  resMsg := 'Завершено!';
  Synchronize(SyncThr);     
end;

//string + дополненительное сообщение от портала
function TEInvVatService.ExceptionMessage(msg: string): string;
begin
    Result := msg + ': ' + EVatService.LastError;
end;

function TEInvVatService.Stop: boolean;
begin
  result:=true;
  if FStatus = thStopped then exit
  else if FStatus = thRun then
  begin
     FStatus := thPause;    
     if TaskMessageDlg('Подтверждение отмены', 'Прервать процесс взаимодействия с порталом?' , mtConfirmation,[mbYes,mbNO], 0) = mrYes  then   
      FStatus := thStopped    
     else 
     begin
      FStatus := thRun;    
      result := false; 
     end;
  end;     
end;

procedure TEInvVatService.Execute;     
begin
  try
   // try
    if FStatus <> thLocked then
    begin
      FStatus := thRun;
      if FOperation = foSignAndSend then
        SignAndSendOut
      else if FOperation = foCheckStatus then
        CheckStatus
      else
        AddLog('Тип операции не задан');
    end;
        //except
    // on E: Exception do
    //    AddLog(e.ClassName + ' ошибка, с сообщением : ' + e.Message);
    // end;
  finally
    FStatus := thStopped;
    Terminate;
  end;
end;              

//функция по отправке ЭСЧФ на портал
// на входе TList<string> - список с номерами ЭСЧФ в формате УНП-ГОД-Номер (например, 192050981-2020-0000000001)
// файлы xml должны иметь аналогичные наименования
procedure TEInvVatService.SignAndSendOut;
var
  i: TSendInfo;
  filename, f, xsd, fn, TicketIssuerUri,
  InvVatType: string;
  InvVatXml, InvVatTicket, status: Variant;
begin
  //  подключение к порталу ЭСФЧ
  sendinfo.Clear;
  if not Connect then
     Abort;
  for f in invoices do
  begin
    //Чтение файла
    filename := files_path + 'invoice-' + f + '.xml';
    InvVatXml := EVatService.CreateEDoc;
    if InvVatXml.Document.LoadFromFile[filename] <> 0 then
      i := TSendInfo.Create(f, True, ExceptionMessage('Ошибка чтения файла'))
    else
    begin
      //Проверка XML файла на соответствие  xsd-схеме
      InvVatType := InvVatXml.Document.GetXmlNodeValue['issuance/general/documentType'];
      if InvVatType = 'ORIGINAL' then
        xsd := 'MNSATI_original.xsd'
      else if InvVatType = 'FIXED' then
        xsd := 'MNSATI_fixed.xsd'
      else if InvVatType = 'ADDITIONAL' then
        xsd := 'MNSATI_additional.xsd'
      else if InvVatType = 'ADD_NO_REFERENCE' then
        xsd := 'MNSATI_add_no_reference.xsd'
      else xsd:='';

      if xsd='' then
        i := TSendInfo.Create(f, True, ExceptionMessage('Файл .xml содержит неверный тип документа'))
      else if InvVatXml.Document.ValidateXML[files_path + 'xsd\' + xsd, 0] <> 0 then
        i := TSendInfo.Create(f, True, ExceptionMessage('Документ не соответствует требуемой схеме xsd'))
      else if InvVatXml.Sign[0] <> 0 then
        i := TSendInfo.Create(f, True, ExceptionMessage('Ошибка выработки подписи'))
      else
      begin
        //Сохранение подписанного файла с расширением '.edoc.xml'
        //fn := filename + '.edoc.xml';
        //if InvVatXml.SaveToFile[fn] <> 0 then
        //   DialogStop(ExceptionMessage('Ошибка сохранения подписанного документа'));

        //Отправка подписанного документа на портал ЭСФЧ
        if EVatService.SendEDoc[InvVatXml] <> 0 then
          i := TSendInfo.Create(f, True, ExceptionMessage('Ошибка отправки'))
        else
        begin
          //Ответ от портала ЭСФЧ будет сохранен в фале с расширением '.ticket.error.xml' в случае
          // ошибки  и с   '.ticket.xml'  в случае успешного принятия файла сервисом
          InvVatTicket := EVatService.Ticket;
          if InvVatTicket.Accepted <> 0 then
          begin
            i := TSendInfo.Create(f, True, 'Документ не принят: ' + InvVatTicket.Message);
            fn := files_path + f + '.ticket.error.xml';
          end
          else
          begin
            //Если документ принят порталом, то мы всё равно пытаемся получить его статус, так как портал может принять документ
            //но по результатам форматно-логического контроля не добавить его
            status := EVatService.GetStatus[f];
            if VarIsNull(status) then
              i := TSendInfo.Create(f, True, 'ЭСЧФ не прошёл проверку на портале статус не принят')
            else
            begin
              if (status.Verify <> 0) then
                i := TSendInfo.Create(f, True, ExceptionMessage('Ошибка получения статуса'))
              else
              begin
                if (status.Status = 'NOT_FOUND') then
                  i := TSendInfo.Create(f, True, 'ЭСЧФ не прошёл проверку на портале ('+ status.Message + ')')
                else
                begin
                  if (status.Status = 'ERROR') then
                    i := TSendInfo.Create(f, True, status.Message)
                  else
                    i := TSendInfo.Create(f, false, InvVatTicket.Message, GetStatusInt(status.Status));
                end;
              end;
            end;      
           // fn := filename + '.ticket.xml';
          end;
         { // Сохранение квитанции
          if InvVatTicket.SaveToFile[fn] <> 0 then
            ShowMessage(ExceptionMessage('Ошибка сохранения квитанции'))
          else
            resMsg := resMsg + #10#13 + ('Файл квитанции ' + fn + ' сохранен');    }
        end;
      end;
    end;
    if not i.IsException then
    begin
     TicketIssuerUri := InvVatTicket.Document.GetXmlNodeAttribute['ticket/issuer/URI'];
     resMsg := 'Документ успешно принят сервисом ' + TicketIssuerUri;
    end
    else
     resMsg := 'Ошибка: '+i.ResMessage;
    resMsg := i.VatInvoice + ' - ' + resMsg;
    inc(Progress);
    Synchronize(SyncThr);
    sendinfo.Add(i);
    while FStatus = thPause do
    begin
      //бесконечный цикл на время паузы
      Sleep(500);
    end;
  end;
end;

procedure TEInvVatService.SyncThr;
begin 
  fmEInvVatServiceLoad.mResult.Lines.Add(resMsg);
  fmEInvVatServiceLoad.cxProgressBar1.Position := Progress;
  if Terminated then
    fmEInvVatServiceLoad.edStatus.Text :='Выполнено';
end;

procedure TEInvVatService.AddLog(msg:string);
begin
  resMsg:=msg;
  Synchronize(SyncThr);
end;

procedure TEInvVatService.CheckStatus;
var
  f: string;
  status: Variant;
  i: TSendInfo;
begin
  sendinfo.Clear;
  //  подключение к порталу ЭСФЧ
  if not Connect then
     Abort;
  for f in invoices do
  begin
    status := EVatService.GetStatus[f];
    if not VarIsNull(status) then
    begin
      if (status.Verify <> 0) then
        i:= TSendInfo.Create(f, True, 'Ошибка верификации статуса')
      else
        i:=TSendInfo.Create(f, False, status.Message, GetStatusInt(status.status));
    end
    else
        i:=TSendInfo.Create(f, True, 'Cтатус от портала не получен');
    Inc(Progress);
    if i.IsException or (i.Status = 0) then
      resMsg := i.VatInvoice + ' - Ошибка: ' +  i.ResMessage
    else
      resMsg := i.VatInvoice + ' - Статус: ' + TCaprionStatus[i.Status];
    Synchronize(SyncThr);
    sendinfo.Add(i);
  end;
end;


function TEInvVatService.GetStatusInt(s: string): Integer;
var
  i: integer;
begin
  result := 0;
  for i := 1 to 8 do
    if TInvoiceStatus[i] = s then
    begin
      Result := i;
      Break;
    end;
end;

{  не обработанные процедуры из C#
public IEnumerable<LoadInfo> LoadIncomeVatInvoice(DateTime date)
begin
            var info = new List<LoadInfo>();

            var removeXmlDeclarationRegex = new Regex(@"<\?xml.*\?>");

            Connect();
            var list = connector.GetList[date.ToString("s")];
            if (list != null)
            begin
                var listCount = list.Count;

                for (var i = 0; i < listCount; i++)
                begin
                    var number = list.GetItemAttribute[i, @"document/number"];
                    var eDoc = connector.GetEDoc[number];
                    if (eDoc != null)
                    begin
                        var verifySign = eDoc.VerifySign[0, 0];
                        if (verifySign == 0)
                        begin
                            var signXml = Encoding.UTF8.GetString(Convert.FromBase64String(eDoc.GetData[1]));
                            var xml = Encoding.UTF8.GetString(Convert.FromBase64String(eDoc.Document.GetData[1]));

                            xml = removeXmlDeclarationRegex.Replace(xml, "");

                            var invoice = serializer.Deserialize(xml);

                            info.Add(new LoadInfo(invoice, number, xml, signXml));
                        end;
                    end;
                end;
            end;
            else
            begin
                ThrowException("Ошибка получения списка ЭСЧФ ");
            end;
            Disconnect();

            return info;
        end;
end;        }
{
public IEnumerable<SendInInfo> SignAndSendIn(params VatInvoiceXml[] invoices)
        begin
            var info = new List<SendInInfo>();
            Connect();
                invoices.ToList().ForEach(x =>
                begin
                    SendInInfo i;
                    var eDoc = connector.CreateEDoc;
                    if (eDoc.SetData[Convert.ToBase64String(Encoding.UTF8.GetBytes(x.SignXml)), 1] != 0)
                        i = new SendInInfo(x, true, ExceptionMessage("Ошибка загрузки информации "));
                    else
                    begin

                        var signCount = eDoc.GetSignCount;
                        if (signCount == 0)
                            i = new SendInInfo(x, true, ExceptionMessage("Документ не содержит ЭЦП "));
                        else begin
                           // if (eDoc.VerifySign[1, 0] != 0)
                           //     i = new SendInInfo(x, true, ExceptionMessage("Ошибка проверки подписи "));
                           // else
                            begin
                                if (eDoc.Sign[0] != 0)
                                    i = new SendInInfo(x, true, ExceptionMessage("Ошибка подписи"));
                                else
                                begin
                                    if (connector.SendEDoc[eDoc] != 0)
                                        i = new SendInInfo(x, true, ExceptionMessage("Ошибка отправки"));
                                    else
                                    begin
                                        var ticket = connector.Ticket;

                                        if (ticket.Accepted != 0)
                                        begin
                                            i = new SendInInfo(x, true, ticket.Message);
                                        end;
                                        else
                                        begin
                                            x.Sign2Xml =
                                                Encoding.UTF8.GetString(Convert.FromBase64String(eDoc.GetData[1]));

                                            i = new SendInInfo(
                                                x,
                                                false,
                                                ticket.Message
                                                );
                                        end;
                                    end;
                                end;
                            end;
                        end;
                    end;

                    info.Add(i);

                end;);
            Disconnect();
            return info;
        end;                 }

end.

