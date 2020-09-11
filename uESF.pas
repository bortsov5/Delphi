unit uESF;
// Создание xml для электронной счетфактуры


interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, dxmdaset, HTTPSend, WinInet, synacode, ZDataset,
  uResourceForms, uResource, xmldom, XMLIntf, msxmldom, XMLDoc, Xml.xmlutil;


function ESF(qf, qESF, q, qNach:TZQuery; period:string;dop: boolean=false): string;


implementation


Function ConvertFloatField(fieldValue:string; EmptyToNULL: boolean=false):string;
Begin
  Result := fieldValue;
  if (Result='') then
    if EmptyToNULL then begin//Может всегда так поступать?
      Result:='NULL'; exit;
    end;
  if FormatSettings.DecimalSeparator='.' then exit;
  If (pos(FormatSettings.DecimalSeparator,fieldValue)>0) Then
    Result[pos(FormatSettings.DecimalSeparator,fieldValue)]:='.';
End;


function AddLeadZero (
      const Number, Length : integer) : string;
 begin
    result := Format('%.*d', [Length, Number]) ;
 end;

function ESF(qf, qESF, q, qNach:TZQuery; period:string; dop: boolean=false): string;
var
  sh:string;
  temp_path,files_path, log_message, files_for_check, str_error, seria, nomer: string;
  signer_path, bat_path: PAnsiChar;
  XMLDoc: TXMLDocument;
  Node, SubNode, Sub2Node, SubNodeGn: IXMLNode;
  SubNodeGnSub, SubNodePrSub, SubNodePr, SubNodeRSub, SubNodeR, Sub3Node, Sub4Node, Sub5Node, Sub6Node, Sub7Node: IXMLNode;
  files, date_now: string;
  count_message:integer;
  order_id:string;
  del_esf:boolean;  //признак отмены ЭСЧФ
  status_post:string;
  status_client:string;
  doc_type: integer;
  FileName:string;

  all_summ, all_mest, all_massa, all_summ_nds ,
  all_summ_with_nds, all_ostatok, all_mest_formula, all_posil: double;
  nds, sum, sum_nds, summ_with_nds: double;
  quantity: integer;
  nds_name, desc_type: string;
  dop_n, unp_seller:string;
  d,m,y:word;
  h, mm, ss, ms:word;

  F : TextFile;
  xml_s:UTF8String;
  i:integer;
  k:integer;
begin
    DecodeDate(Date+time, y, m, d);
    DecodeTime(Date+time, h, mm, ss, ms);
    temp_path:= Resource.ModuleInfo.TempDir;
    files_path := ExtractFileDir(ExtractFilePath(Application.ExeName)) +'\ForSign\';
    status_post:= 'SELLER'; //Продавец
    status_client:= 'CUSTOMER'; //Потребитель
    {
      ТН-2 602
      ТТН-1  603
      Договор   604
      Контракт 605
      Другое  601
      Акт   606
      CMR-накладная  607
      Счет-фактура   608
      Invoice (счет) 609
      Авизо  610
      Бухгалтерская справка  611
      Акт выполненных работ 612
      Коносамент 613
      ЭТТН  614
    }
   doc_type:= 612;
   unp_seller:='*****'; //qf.FieldByName('unp').AsString;


    try
      ForceDirectories(files_path);
    except
      //Создадим директорию, если ее нет
    end;

    files := '';
    del_esf:=false;

    XMLDoc:=TXMLDocument.Create(nil);

            XMLDoc.XML.Clear;
            XMLDoc.Active := True;
            XMLDoc.Encoding := 'UTF-8';
            Node := XMLDoc.AddChild('issuance');

           // Node.SetAttribute('xmlns',  UTF8Encode('http://www.w3schools.com'));
            Node.SetAttribute('sender', UTF8Encode(unp_seller));
            Node.SetAttribute('xmlns:xsi', UTF8Encode('http://www.w3.org/2001/XMLSchema-instance'));
            Node.SetAttribute('xmlns:xs',  UTF8Encode('http://www.w3.org/2001/XMLSchema'));
            Node.DeclareNamespace('',UTF8Encode('http://www.w3schools.com'));


            if dop then
            begin
              SubNode:=XMLDoc.CreateElement('system','http://www.w3schools.com'); //создали узел
              XMLDoc.DocumentElement.ChildNodes.Add(SubNode); //записали документ
              Sub2Node := SubNode.AddChild('modelVersion');
              Sub2Node.NodeValue:='1.0.0';
            end;

              SubNodeGn:=XMLDoc.CreateElement('general','http://www.w3schools.com'); //создали узел
              XMLDoc.DocumentElement.ChildNodes.Add(SubNodeGn); //записали документ


                SubNodeGnSub :=SubNodeGn.AddChild('number');
                order_id:=IntToStr(qESF.FieldByName('v_order_id').AsInteger);

                if not dop then
                 begin

                    dop_n:='01';
                    date_now := FormatDateTime('YYYYMMDDHHNNSS', Now);
                    SubNodeGnSub.NodeValue := unp_seller+'-'+FormatDateTime('YYYY', Now)
                                        +'-'+dop_n+AddLeadZero(strtoint(order_id),8);
                 end else
                 begin

                    SubNodeGnSub.NodeValue := qESF.FieldByName('v_eshf_numb').AsString;

                 end;

                 SubNodeGnSub := SubNodeGn.AddChild('dateIssuance');
                 SubNodeGnSub.NodeValue := FormatDateTime('YYYY-MM-DD', qESF.FieldByName('v_order_date').AsDateTime);
                 SubNodeGnSub := SubNodeGn.AddChild('dateTransaction');
                 SubNodeGnSub.NodeValue := FormatDateTime('YYYY-MM-DD', Now);
                 if dop then
                 begin
                    SubNodeGnSub := SubNodeGn.AddChild('documentType');
                    SubNodeGnSub.NodeValue := UTF8Encode('ADDITIONAL');
                    SubNodeGnSub :=SubNodeGn.AddChild('invoice');
                    dop_n:='02';
                    SubNodeGnSub.NodeValue := unp_seller+'-'+FormatDateTime('YYYY', Now)+'-'+dop_n+AddLeadZero(strtoint(order_id),8);
                    SubNodeGnSub :=SubNodeGn.AddChild('sendToRecipient');
                    SubNodeGnSub.NodeValue := 'true';
                 end
                 else begin
                    SubNodeGnSub := SubNodeGn.AddChild('documentType');
                    SubNodeGnSub.NodeValue := UTF8Encode('ORIGINAL')
                 end;




                 if not dop then
                 begin
                    SubNodePr := Node.AddChild('provider','http://www.w3schools.com');
                    SubNodePrSub := SubNodePr.AddChild('providerStatus');    //6. Статус поставщика
                    SubNodePrSub.NodeValue := UTF8Encode(status_post);
                    SubNodePrSub := SubNodePr.AddChild('dependentPerson');  //"6.1. Взаимозависимое лицо Правило 7. false, если составитель ЭСЧФ получатель"
                    SubNodePrSub.NodeValue := UTF8Encode('false');
                    SubNodePrSub := SubNodePr.AddChild('residentsOfOffshore');  //"6.2. Сделка с резидентом оффшорной зоны Правило 7. false, если составитель ЭСЧФ получатель"
                    SubNodePrSub.NodeValue := UTF8Encode('false');
                    SubNodePrSub := SubNodePr.AddChild('specialDealGoods'); //
                    SubNodePrSub.NodeValue := UTF8Encode('false');
                    SubNodePrSub := SubNodePr.AddChild('bigCompany');
                    SubNodePrSub.NodeValue := UTF8Encode('true');
                    SubNodePrSub := SubNodePr.AddChild('countryCode');
                    SubNodePrSub.NodeValue := '112';
                    SubNodePrSub := SubNodePr.AddChild('unp');   //"8. УНП
                                                            //ФОРМАТ: 9 цифр для юр. лиц и ИП и 2буквы и 7 цифр для физ. лиц
                                                            //Правило 10. Если статус поставщика (реквиз №6 не иностранная организация),
                                                            //то УНП поставщика = УНП составляющего ЭСЧФ (реквизит №1)"
                    SubNodePrSub.NodeValue := unp_seller;
                    SubNodePrSub := SubNodePr.AddChild('name');
                    SubNodePrSub.NodeValue := UTF8Encode(qf.FieldByName('name').AsString+' РБ');  //9. Юридическое наименование поставщика
                    SubNodePrSub := SubNodePr.AddChild('address');
                    SubNodePrSub.NodeValue := UTF8Encode('220049, '+qf.FieldByName('adr').AsString);   //10. Юридический адрес

                    //---------------------

                    SubNodeR := Node.AddChild('recipient','http://www.w3schools.com');
                    SubNodeRSub := SubNodeR.AddChild('recipientStatus');
                    SubNodeRSub.NodeValue := UTF8Encode(status_client);
                    SubNodeRSub := SubNodeR.AddChild('dependentPerson');  //15.1. Взаимозависимое лицо
                    SubNodeRSub.NodeValue := UTF8Encode('false');
                    SubNodeRSub := SubNodeR.AddChild('residentsOfOffshore');  //15.2. Сделка с резидентом оффшорной зоны
                    SubNodeRSub.NodeValue := UTF8Encode('false');
                    SubNodeRSub := SubNodeR.AddChild('specialDealGoods');
                    SubNodeRSub.NodeValue := UTF8Encode('false');
                    SubNodeRSub := SubNodeR.AddChild('bigCompany');     //15.4. Организация, включенная в перечень крупных плательщиков
                    SubNodeRSub.NodeValue := UTF8Encode('false');
                    SubNodeRSub := SubNodeR.AddChild('countryCode');  //16. Код страны получателя
                    SubNodeRSub.NodeValue := '112';
                    SubNodeRSub := SubNodeR.AddChild('unp');    //17. УНП получателя
                    SubNodeRSub.NodeValue := qESF.FieldByName('v_cust_unp').AsString;
                    SubNodeRSub := SubNodeR.AddChild('name');                         //18. Юридическое наименование получателя
                    SubNodeRSub.NodeValue := UTF8Encode(qESF.FieldByName('v_cust_name').AsString);
                    SubNodeRSub := SubNodeR.AddChild('address');
                    SubNodeRSub.NodeValue := UTF8Encode(qESF.FieldByName('v_cust_adr').AsString);

                     //--------------------

                    Sub2Node := Node.AddChild('senderReceiver', 'http://www.w3schools.com');
                    Sub3Node := Sub2Node.AddChild('consignors');
                    Sub4Node := Sub3Node.AddChild('consignor');
                    Sub5Node := Sub4Node.AddChild('countryCode');  //22. Код страны грузоотправителя
                    Sub5Node.NodeValue := '112';
                    Sub5Node := Sub4Node.AddChild('unp');       //23. УНП грузоотправителя
                      Sub5Node.NodeValue := unp_seller;
                    Sub5Node := Sub4Node.AddChild('name');
                    Sub5Node.NodeValue := UTF8Encode(qf.FieldByName('name').AsString);
                    Sub5Node := Sub4Node.AddChild('address');
                    Sub5Node.NodeValue := UTF8Encode('220049, '+qf.FieldByName('adr').AsString);

                    Sub3Node := Sub2Node.AddChild('consignees');
                    Sub4Node := Sub3Node.AddChild('consignee');
                    Sub5Node := Sub4Node.AddChild('countryCode');
                    Sub5Node.NodeValue := '112';     //26. Код страны грузополучателя
                    Sub5Node := Sub4Node.AddChild('unp');
                    Sub5Node.NodeValue := qESF.FieldByName('v_cust_unp').AsString; //27. УНП грузополучателя
                    Sub5Node := Sub4Node.AddChild('name');
                    Sub5Node.NodeValue := UTF8Encode(qESF.FieldByName('v_cust_name').AsString);  //28. Юридическое наименование грузополучателя
                    Sub5Node := Sub4Node.AddChild('address');
                    Sub5Node.NodeValue := UTF8Encode(qESF.FieldByName('v_cust_adr').AsString);    //29. Адрес доставки

                    //------------------

                   end;

                    Sub2Node := Node.AddChild('deliveryCondition','http://www.w3schools.com');
                    Sub3Node := Sub2Node.AddChild('contract');
                    Sub4Node := Sub3Node.AddChild('number');       //30. Договор (контракт) на поставку товара.
                    Sub4Node.NodeValue := UTF8Encode(qESF.FieldByName('v_contract_number').AsString);
                    Sub4Node := Sub3Node.AddChild('date');  //30. Дата договора (контракта).
                    Sub4Node.NodeValue := FormatDateTime('YYYY-MM-DD', qESF.FieldByName('v_order_date').AsDateTime);
                    Sub4Node := Sub3Node.AddChild('documents');
                    Sub5Node := Sub4Node.AddChild('document');
                    Sub6Node := Sub5Node.AddChild('docType');
                    Sub7Node := Sub6Node.AddChild('code');
                    Sub7Node.NodeValue:= IntToStr(doc_type); //Код вида документа
                    Sub6Node := Sub5Node.AddChild('date');
                    Sub6Node.NodeValue := FormatDateTime('YYYY-MM-DD', qESF.FieldByName('v_order_date').AsDateTime);

                    Sub6Node := Sub5Node.AddChild('seria');
                    Sub6Node.NodeValue :=  '';
                    Sub6Node := Sub5Node.AddChild('number');
                    Sub6Node.NodeValue := UTF8Encode(qESF.FieldByName('v_order_number').AsString);

                    if dop then
                       begin
                          Sub6Node := Sub5Node.AddChild('refund');
                          Sub6Node.NodeValue := 'false';

                          Sub3Node := Sub2Node.AddChild('description');
                       end;

                    //---  СОСТАВ

                      all_summ := 0; all_mest := 0; all_massa := 0;
                      all_summ_nds := 0; all_summ_with_nds := 0;
                      all_ostatok := 0; all_mest_formula := 0; all_posil := 0;

                       qNach.Close;
                       qNach.SQL.Text:='select * from bul.bnach_detail_get2(:order_id)';
                       qNach.Params.ParamByName('order_id').Value:=order_id;
                       qNach.Open;

                       qNach.first;
                      while not qNach.Eof do
                          begin
                            // nds := qESF.FieldByName('v_summa_nds').AsInteger;
                            // sum := qESF.FieldByName('v_summa').AsFloat-qESF.FieldByName('v_summa_nds').AsInteger;
                            all_summ := all_summ+(qNach.FieldByName('v_nach').AsFloat-qNach.FieldByName('v_nach_nds').AsFloat);//all_summ + sum;
                            //  sum_nds := qESF.FieldByName('v_summa_nds').AsFloat;
                            all_summ_nds := all_summ_nds + qNach.FieldByName('v_nach_nds').AsFloat;
                            //  summ_with_nds := qESF.FieldByName('v_summa').AsFloat;
                            all_summ_with_nds := all_summ_with_nds + qNach.FieldByName('v_nach').AsFloat;

                            qNach.next;
                          end;


                      Sub2Node := Node.AddChild('roster','http://www.w3schools.com');
                      Sub2Node.SetAttribute('totalCost', ConvertFloatField(FloatToStr(all_summ)));
                      Sub2Node.SetAttribute('totalVat', ConvertFloatField(FloatToStr(all_summ_nds)));
                      Sub2Node.SetAttribute('totalExcise', ConvertFloatField(FloatToStr(0)));
                      Sub2Node.SetAttribute('totalCostVat', ConvertFloatField(FloatToStr(all_summ_with_nds)));



                          qNach.First;
                          while not qNach.Eof do  //!!!!
                          begin

                            Sub3Node := Sub2Node.AddChild('rosterItem');
                            Sub4Node := Sub3Node.AddChild('number');
                            Sub4Node.NodeValue := IntToStr(qNach.RecNo);
                            Sub4Node := Sub3Node.AddChild('name');
                            Sub4Node.NodeValue := UTF8Encode(qNach.FieldByName('v_mainattr').AsString);
                          //  Sub4Node := Sub3Node.AddChild('code');
                          //  Sub4Node.NodeValue := '';
                          //  Sub4Node := Sub3Node.AddChild('units');
                          //  Sub4Node.NodeValue := '796';
                            Sub4Node := Sub3Node.AddChild('count');
                            Sub4Node.NodeValue := qNach.FieldByName('v_koled').AsString;
                            Sub4Node := Sub3Node.AddChild('price');
                            Sub4Node.NodeValue := '0';

                            quantity := qESF.FieldByName('v_koled').AsInteger;
                            sum := qNach.FieldByName('v_nach').AsFloat-qNach.FieldByName('v_nach_nds').AsFloat;

                            Sub4Node := Sub3Node.AddChild('cost');
                            Sub4Node.NodeValue := ConvertFloatField(FloatToStr(sum));
                            Sub4Node := Sub3Node.AddChild('summaExcise');  //8. В том числе сумма акциза, бел. руб
                            Sub4Node.NodeValue := '0';
                            Sub4Node := Sub3Node.AddChild('vat');
                            Sub5Node := Sub4Node.AddChild('rate');  //9.1. Ставка НДС
                            Sub5Node.NodeValue := qNach.FieldByName('v_nds').AsString;
                             nds_name:= 'DECIMAL';
                            if qNach.FieldByName('v_nds').AsInteger=0 then
                              nds_name:= 'ZERO';

                            Sub5Node := Sub4Node.AddChild('rateType');
                            Sub5Node.NodeValue := UTF8Encode(nds_name);
                            nds := qNach.FieldByName('v_nds').AsInteger;
                            sum_nds :=  qNach.FieldByName('v_nach_nds').AsFloat;
                            summ_with_nds :=  qNach.FieldByName('v_nach').AsFloat;
                            Sub5Node := Sub4Node.AddChild('summaVat');
                            Sub5Node.NodeValue := ConvertFloatField(FloatToStr(sum_nds));
                            Sub4Node := Sub3Node.AddChild('costVat');
                            Sub4Node.NodeValue := ConvertFloatField(FloatToStr(summ_with_nds));
                            if qNach.FieldByName('v_nds').AsInteger=0  then
                            begin
                              Sub4Node := Sub3Node.AddChild('descriptions');
                              desc_type:= 'VAT_EXEMPTION';
                              Sub5Node := Sub4Node.AddChild('description');
                              Sub5Node.NodeValue := UTF8Encode(desc_type);
                            end;
                            qNach.Next;
                          end;


            log_message:='Создание ЭСЧФ';
            FileName := files_path + 'invoice-'+unp_seller+'-'+inttostr(y)+'-'+dop_n+AddLeadZero(strtoint(order_id),8)+'.xml';

            xmlDoc.SaveToFile(FileName);
            files := files + '"' + FileName + '" ';

            result:= FileName;
end;


{
function ESF(qf, qESF, q, qNach:TZQuery; period:string): string;
var
  sh:string;
  temp_path,files_path, log_message, files_for_check, str_error, seria, nomer: string;
  signer_path, bat_path: PAnsiChar;
  XMLDoc: TXMLDocument;
  Node, SubNode, Sub2Node, Sub3Node, Sub4Node, Sub5Node, Sub6Node, Sub7Node: IXMLNode;
  files, date_now: string;
  count_message:integer;
  order_id:string;
  del_esf:boolean;  //признак отмены ЭСЧФ
  status_post:string;
  status_client:string;
  doc_type: integer;
  FileName:string;

  all_summ, all_mest, all_massa, all_summ_nds ,
  all_summ_with_nds, all_ostatok, all_mest_formula, all_posil: double;
  nds, sum, sum_nds, summ_with_nds: double;
  quantity: integer;
  nds_name, desc_type: string;
  dop_n:string;
begin
    temp_path:= Resource.ModuleInfo.TempDir;
    files_path := ExtractFileDir(ExtractFilePath(Application.ExeName)) +'\ForSign\';
    status_post:= 'SELLER'; //Продавец
    status_client:= 'CONSUMER'; //Потребитель

   //   ТН-2 602
   //   ТТН-1  603
    //  Договор   604
   //   Контракт 605
   //   Другое  601
   //   Акт   606
   //   CMR-накладная  607
   //   Счет-фактура   608
   //   Invoice (счет) 609
   //   Авизо  610
   //   Бухгалтерская справка  611
   //   Акт выполненных работ 612
   //   Коносамент 613
   //   ЭТТН  614
    //
doc_type:= 608;


    try
      ForceDirectories(files_path);
    except
      //Создадим директорию, если ее нет
    end;

    files := '';
    del_esf:=false;

    XMLDoc:=TXMLDocument.Create(nil);

    XMLDoc.XML.Clear;
            XMLDoc.Active := True;
            XMLDoc.Encoding := 'UTF-8';
            Node := XMLDoc.AddChild('BLRNDS');
            Node.SetAttribute('version', '0.1');
            Node.DeclareNamespace('',UTF8Encode('http://www.w3schools.com'));
            date_now := FormatDateTime('YYYYMMDDHHNNSS', Now);

            count_message := qESF.FieldByName('v_max_mess_id').AsInteger;

            order_id:=IntToStr(qESF.FieldByName('v_order_id').AsInteger);
            while Length(order_id)<10 do
              order_id:= '0'+order_id;

            SubNode := Node.AddChild('MessageHeader', 'http://www.w3schools.com');
            Sub2Node := SubNode.AddChild('MessageID');
            Sub2Node.NodeValue := IntToStr(count_message);
            Sub2Node := SubNode.AddChild('MsgDateTime');
            Sub2Node.NodeValue := date_now;
            Sub2Node := SubNode.AddChild('MessageType');
            Sub2Node.NodeValue := UTF8Encode('BLRNDS');
            Sub2Node := SubNode.AddChild('MsgSenderID');
            Sub2Node.NodeValue := '**********';       //?????
            Sub2Node := SubNode.AddChild('MsgReceiverID');
            Sub2Node.NodeValue := '9000000000001';       //?????
            Sub2Node := SubNode.AddChild('TestIndicator'); //удалить когда выложим рабочую версию поле не обязательное
            Sub2Node.NodeValue := '1';                     //удалить когда выложим рабочую версию поле не обязательное
            Sub2Node := SubNode.AddChild('UserID');
            Sub2Node.NodeValue := Resource.ModuleInfo.FIO;

            SubNode := XMLDoc.AddChild('issuance');
            SubNode.DeclareNamespace('',UTF8Encode('http://www.w3schools.com'));
            SubNode.SetAttribute('sender',qf.FieldByName('bik').AsString);
            Sub2Node := SubNode.AddChild('general', 'http://www.w3schools.com');
            Sub3Node := Sub2Node.AddChild('number');
            dop_n:='01';
            if qESF.FieldByName('v_summa').AsFloat<=0 then dop_n:='02';

            Sub3Node.NodeValue := qf.FieldByName('unp').AsString+'-'+FormatDateTime('YYYY', Now)
                                +'-'+dop_n+AddLeadZero(strtoint(order_id),8);
            Sub3Node := Sub2Node.AddChild('dateTransaction');
            if del_esf then
              Sub3Node.NodeValue := FormatDateTime('YYYY-MM-DD', Now)
            else
            Sub3Node.NodeValue := FormatDateTime('YYYY-MM-DD', qESF.FieldByName('v_order_date').AsDateTime);
            Sub3Node := Sub2Node.AddChild('documentType');
            if del_esf then
              Sub3Node.NodeValue := UTF8Encode('FIXED')
            else begin
                Sub3Node.NodeValue := UTF8Encode('ORIGINAL')
             end;
            if del_esf then
            begin
              Sub3Node := Sub2Node.AddChild('invoice');
              if qESF.FieldByName('v_eshf_numb').IsNull then
                Sub3Node.NodeValue := UTF8Encode(qESF.FieldByName('v_max_mess_id').AsString)
              else Sub3Node.NodeValue := UTF8Encode(qESF.FieldByName('v_eshf_numb').AsString);
            end;
            if del_esf then begin
              Sub3Node := Sub2Node.AddChild('dateCancelled');
              Sub3Node.NodeValue := FormatDateTime('YYYY-MM-DD', qESF.FieldByName('order_date').AsDateTime);
            end;
            //здесь идут поля для оригинала и исправленного
            if del_esf then
            begin
              Sub2Node := SubNode.AddChild('provider','http://www.w3schools.com');
              Sub3Node := Sub2Node.AddChild('providerStatus');    //6. Статус поставщика
              Sub3Node.NodeValue := UTF8Encode(status_post);
              Sub3Node := Sub2Node.AddChild('dependentPerson');  //"6.1. Взаимозависимое лицо Правило 7. false, если составитель ЭСЧФ получатель"
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('residentsOfOffshore');  //"6.2. Сделка с резидентом оффшорной зоны Правило 7. false, если составитель ЭСЧФ получатель"
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('specialDealGoods'); //
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('bigCompany');
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('countryCode');
              Sub3Node.NodeValue := '112';
              Sub3Node := Sub2Node.AddChild('unp');   //"8. УНП
                                                      //ФОРМАТ: 9 цифр для юр. лиц и ИП и 2буквы и 7 цифр для физ. лиц
                                                      //Правило 10. Если статус поставщика (реквиз №6 не иностранная организация),
                                                      //то УНП поставщика = УНП составляющего ЭСЧФ (реквизит №1)"
              Sub3Node.NodeValue := qf.FieldByName('unp').AsString;
              Sub3Node := Sub2Node.AddChild('name');
              Sub3Node.NodeValue := UTF8Encode(qf.FieldByName('name').AsString);  //9. Юридическое наименование поставщика
              Sub3Node := Sub2Node.AddChild('address');
              Sub3Node.NodeValue := UTF8Encode(qf.FieldByName('adr').AsString);   //10. Юридический адрес
              Sub2Node := SubNode.AddChild('recipient','http://www.w3schools.com');
              Sub3Node := Sub2Node.AddChild('recipientStatus');
              Sub3Node.NodeValue := UTF8Encode(status_client);
              Sub3Node := Sub2Node.AddChild('dependentPerson');  //15.1. Взаимозависимое лицо
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('residentsOfOffshore');  //15.2. Сделка с резидентом оффшорной зоны
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('specialDealGoods');
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('bigCompany');     //15.4. Организация, включенная в перечень крупных плательщиков
              Sub3Node.NodeValue := UTF8Encode('false');
              Sub3Node := Sub2Node.AddChild('countryCode');  //16. Код страны получателя
              Sub3Node.NodeValue := '112';
              Sub3Node := Sub2Node.AddChild('unp');    //17. УНП получателя
              Sub3Node.NodeValue := qESF.FieldByName('v_cust_unp').AsString;
              Sub3Node := Sub2Node.AddChild('name');                         //18. Юридическое наименование получателя
              Sub3Node.NodeValue := UTF8Encode(qESF.FieldByName('v_cust_name').AsString);
              Sub3Node := Sub2Node.AddChild('address');
              Sub3Node.NodeValue := UTF8Encode(qESF.FieldByName('v_cust_adr').AsString);
              Sub2Node := SubNode.AddChild('senderReceiver', 'http://www.w3schools.com');
              Sub3Node := Sub2Node.AddChild('consignors');
              Sub4Node := Sub3Node.AddChild('consignor');
              Sub5Node := Sub4Node.AddChild('countryCode');  //22. Код страны грузоотправителя
              Sub5Node.NodeValue := '112';
              Sub5Node := Sub4Node.AddChild('unp');       //23. УНП грузоотправителя
                Sub5Node.NodeValue := qf.FieldByName('unp').AsString;
              Sub5Node := Sub4Node.AddChild('name');
              Sub5Node.NodeValue := UTF8Encode(qf.FieldByName('name').AsString);
              Sub5Node := Sub4Node.AddChild('address');
              Sub5Node.NodeValue := UTF8Encode(qf.FieldByName('adr').AsString);

              Sub3Node := Sub2Node.AddChild('consignees');
              Sub4Node := Sub3Node.AddChild('consignee');
              Sub5Node := Sub4Node.AddChild('countryCode');
              Sub5Node.NodeValue := '112';     //26. Код страны грузополучателя
              Sub5Node := Sub4Node.AddChild('unp');
              Sub5Node.NodeValue := qf.FieldByName('unp').AsString; //27. УНП грузополучателя
              Sub5Node := Sub4Node.AddChild('name');
              Sub5Node.NodeValue := UTF8Encode(qf.FieldByName('name').AsString);  //28. Юридическое наименование грузополучателя
              Sub5Node := Sub4Node.AddChild('address');
              Sub5Node.NodeValue := UTF8Encode(qf.FieldByName('adr').AsString);    //29. Адрес доставки

              Sub2Node := SubNode.AddChild('deliveryCondition','http://www.w3schools.com');
              Sub3Node := Sub2Node.AddChild('contract');
              Sub4Node := Sub3Node.AddChild('number');       //30. Договор (контракт) на поставку товара.
              Sub4Node.NodeValue := UTF8Encode(qESF.FieldByName('v_contract_number').AsString);
              Sub4Node := Sub3Node.AddChild('date');  //30. Дата договора (контракта).
              Sub4Node.NodeValue := FormatDateTime('YYYY-MM-DD', qESF.FieldByName('v_order_date').AsDateTime);
              Sub4Node := Sub3Node.AddChild('documents');
              Sub5Node := Sub4Node.AddChild('document');
              Sub6Node := Sub5Node.AddChild('docType');
              Sub7Node := Sub6Node.AddChild('code');
              Sub7Node.NodeValue:= IntToStr(doc_type); //Код вида документа
              Sub6Node := Sub5Node.AddChild('date');
              Sub6Node.NodeValue := FormatDateTime('YYYY-MM-DD', qESF.FieldByName('v_order_date').AsDateTime);
              Sub6Node := Sub5Node.AddChild('blankCode');
              Sub6Node.NodeValue := '';  //Нет кода
              Sub6Node := Sub5Node.AddChild('seria');
              Sub6Node.NodeValue :=  '';
              Sub6Node := Sub5Node.AddChild('number');
              Sub6Node.NodeValue := UTF8Encode(qESF.FieldByName('v_order_number').AsString);
            end;


            all_summ := 0; all_mest := 0; all_massa := 0;
            all_summ_nds := 0; all_summ_with_nds := 0;
            all_ostatok := 0; all_mest_formula := 0; all_posil := 0;
            qESF.First;
            while not qESF.Eof do
            begin
              nds := qESF.FieldByName('v_summa_nds').AsInteger;
              sum := qESF.FieldByName('v_summa').AsFloat-qESF.FieldByName('v_summa_nds').AsInteger;
              all_summ := all_summ + sum;
              sum_nds := qESF.FieldByName('v_summa_nds').AsFloat;
              all_summ_nds := all_summ_nds + sum_nds;
              summ_with_nds := qESF.FieldByName('v_summa').AsFloat;
              all_summ_with_nds := all_summ_with_nds + summ_with_nds;
              qESF.Next;
            end;

            Sub2Node := SubNode.AddChild('roster','http://www.w3schools.com');
            Sub2Node.SetAttribute('totalCost', ConvertFloatField(FloatToStr(all_summ)));
            Sub2Node.SetAttribute('totalVat', ConvertFloatField(FloatToStr(all_summ_nds)));
            Sub2Node.SetAttribute('totalExcise', ConvertFloatField(FloatToStr(0)));
            Sub2Node.SetAttribute('totalCostVat', ConvertFloatField(FloatToStr(all_summ_with_nds)));
            qESF.First;
            while not qESF.Eof do
            begin
                qNach.Close;
                qNach.SQL.Text:='select * from bul.bnach_detail_get(:id_contract, :period)';
                qNach.Params.ParamByName('id_contract').Value:=qESF.FieldByName('v_contract_id').AsInteger;
                qNach.Params.ParamByName('period').Value:=period;
                qNach.Open;

                qNach.First;
                while not qNach.Eof do  //!!!!
                begin

                  Sub3Node := Sub2Node.AddChild('rosterItem');
                  Sub4Node := Sub3Node.AddChild('number');
                  Sub4Node.NodeValue := IntToStr(qNach.RecNo-1);
                  Sub4Node := Sub3Node.AddChild('name');
                  Sub4Node.NodeValue := UTF8Encode(qNach.FieldByName('v_mainattr').AsString);
                  Sub4Node := Sub3Node.AddChild('code');
                  Sub4Node.NodeValue := '';
                  Sub4Node := Sub3Node.AddChild('units');
                  Sub4Node.NodeValue := '796';
                  Sub4Node := Sub3Node.AddChild('count');
                  Sub4Node.NodeValue := qNach.FieldByName('v_koled').AsString;
                  Sub4Node := Sub3Node.AddChild('price');
                  Sub4Node.NodeValue := '0';

                  quantity := qESF.FieldByName('v_koled').AsInteger;
                  sum := qNach.FieldByName('v_nach').AsFloat-qNach.FieldByName('v_nach_nds').AsFloat;

                  Sub4Node := Sub3Node.AddChild('cost');
                  Sub4Node.NodeValue := ConvertFloatField(FloatToStr(sum));
                  Sub4Node := Sub3Node.AddChild('summaExcise');  //8. В том числе сумма акциза, бел. руб
                  Sub4Node.NodeValue := '0';
                  Sub4Node := Sub3Node.AddChild('vat');
                  Sub5Node := Sub4Node.AddChild('rate');  //9.1. Ставка НДС
                  Sub5Node.NodeValue := qNach.FieldByName('v_nds').AsString;
                   nds_name:= 'DECIMAL';
                  if qNach.FieldByName('v_nds').AsInteger=0 then
                    nds_name:= 'ZERO';

                  Sub5Node := Sub4Node.AddChild('rateType');
                  Sub5Node.NodeValue := UTF8Encode(nds_name);
                  nds := qNach.FieldByName('v_nds').AsInteger;
                  sum_nds :=  qNach.FieldByName('v_nds').AsFloat;
                  summ_with_nds :=  qNach.FieldByName('v_nach').AsFloat;
                  Sub5Node := Sub4Node.AddChild('summaVat');
                  Sub5Node.NodeValue := ConvertFloatField(FloatToStr(sum_nds));
                  Sub4Node := Sub3Node.AddChild('costVat');
                  Sub4Node.NodeValue := ConvertFloatField(FloatToStr(summ_with_nds));
                  if qNach.FieldByName('v_nds').AsInteger=0  then
                  begin
                    Sub4Node := Sub3Node.AddChild('descriptions');
                    desc_type:= 'VAT_EXEMPTION';
                    Sub5Node := Sub4Node.AddChild('description');
                    Sub5Node.NodeValue := UTF8Encode(desc_type);
                  end;
                  qNach.Next;
                end;

            qESF.Next;
            end;


            log_message:='Создание ЭСЧФ';
            FileName := files_path + IntToStr(count_message) + '_' +
            '9000000000001'
            + '_' + '4819001150005' + '.xml';
            XMLDoc.SaveToFile(FileName);
            files := files + '"' + FileName + '" ';

            XMLDoc:=nil;

            result:= FileName;
end;}
end.
