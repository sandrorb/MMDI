#property copyright   "Sandro Boschetti - 05/08/2020"
#property description "Programa implementado em MQL5/Metatrader5"
#property description "Realiza backtests do método MMDI idealizado por mim"
#property link        "http://lattes.cnpq.br/9930983261299053"
#property version     "1.00"

#include <Arrays\List.mqh>
#include <Arrays\ArrayObj.mqh>

//#property indicator_separate_window
#property indicator_chart_window

//--- input parameters
#property indicator_buffers 1
#property indicator_plots   1

//---- plot RSIBuffer
#property indicator_label1  "SrB-MMDI"
#property indicator_type1   DRAW_ARROW //DRAW_LINE
#property indicator_color1  Red //clrGreen//Red
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- input parameters
input string nomeDoMetodo = "SrB-MMDI";   //nome do método
input int periodo = 1;                        //número de períodos
input double capitalInicial = 30000.00;       //Capital Inicial
input int lote = 100;                         //1 para WIN e 100 para ações
input bool reaplicar = false;                 //true: reaplicar o capital
input datetime t1 = D'2015.01.01 00:00:00';   //data inicial
input datetime t2 = D'2020.09.16 00:00:00';   //data final
//input datetime t2 = D'2020.08.09 00:00:01'; //data final

bool   comprado = false;
bool   jaCalculado = false;


//--- indicator buffers
double MyBuffer[];
//--- global variables
//bool tipoExpTeste = tipoExp;


class MyObj : public CObject{
   public:
      string time;
      double rent;
};

int OnInit() {
   SetIndexBuffer(0,MyBuffer,INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME,"SrB-MMDI("+string(periodo)+")");
   return(0);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) {
 
   int nOp = 0;
   double capital = capitalInicial;
   int nAcoes = 0;
   double precoDeCompra = 0;
   double lucroOp = 0;
   double lucroAcum = 0;
   double acumPositivo = 0;
   double acumNegativo = 0;
   int nAcertos = 0;
   int nErros = 0;
   double max = 0;
   
   // Para o cálculo do drawdown máximo
   double capMaxDD = capitalInicial;
   double capMinDD = capitalInicial;
   double rentDDMax = 0.00;
   double rentDDMaxAux = 0.00;
   
   // Essas duas variáveis não tem razão de ser neste método
   int nPregoes = 0;
   int nPregoesPos = 0;
   
   // Essas duas variáveis não tem razão de ser neste método
   datetime diaDaEntrada = time[0];
   double duracao = 0.0;
   
   // percentual dos trades que atingem a máxima. A outra parte sai pelo fechamento.
   double percRompMax = 0.5;
   
   double rentPorTradeAcum = 0.0;
   double percPorTradeGainAcum = 0.0;   
   double percPorTradeLossAcum = 0.0;
   
   CList *rentPorTradeAcumList = new CList;

      
   for(int i=periodo+1; i<rates_total;i++){
   
      if (time[i]>=t1 && time[i]<t2) {
      
         //Essa parte não tem sido usada neste método MMDI já que a posição é de um único dia
         nPregoes++;
         if(comprado){nPregoesPos++;}
      
         // Se posiciona na compra
         if(!comprado){
            //Parece fazer grande diferença se a comparação é com o igual ou não.
            //Embora a comparação com o igual é tem mais a ver com a lógica do método,
            //preferiu-se ser mais conservador sem o igual.
            //if( (open[i]>=low[i-1] && low[i]<=low[i-1]) || (open[i]<=low[i-1] && high[i]>=low[i-1]) ){
            if( (open[i]>low[i-1] && low[i]<low[i-1]) || (open[i]<low[i-1] && high[i]>low[i-1]) ){
               precoDeCompra = low[i-1];
               nAcoes = lote * floor(capital / (lote * precoDeCompra));
               comprado = true;
               nOp++;
               diaDaEntrada = time[i];
               MyBuffer[i] = precoDeCompra;
            } 
         }
         
         // Faz a venda
         if( comprado ){
         
         // A superação da máxima pode ter ocorrido antes da compra. Pode até mesmo ter ocorrido
         // uma segunda superação de máxima, mas não há como saber. Então, no caso de superação
         // da máxima, conservadoramente não atribui-se toda a saída na máxima.
            if (high[i]>=high[i-1]){
               //Não há como saber se o rompimento da máxima anterior ocorreu antes
               //da entrada ser acionada, portanto, faço uma ponderação.
               lucroOp = (high[i-1]*percRompMax + close[i]*(1.0 - percRompMax) - precoDeCompra) * nAcoes;
            }else{
               lucroOp = (close[i] - precoDeCompra) * nAcoes;
            }
            
            if(lucroOp>=0){
               nAcertos++;
               acumPositivo = acumPositivo + lucroOp;
               //rentPositiva = rentPositiva + lucroOp / (nAcoes*precoDeCompra);
            }else{
               nErros++;
               acumNegativo = acumNegativo + lucroOp;
               //rentNegativa = rentNegativa + lucroOp / (nAcoes*precoDeCompra);
            }
            
            lucroAcum = lucroAcum + lucroOp;
            
            if(reaplicar == true){capital = capital + lucroOp;}
            
            rentPorTradeAcum = rentPorTradeAcum + (lucroOp / (nAcoes * precoDeCompra));
            MyObj *myObj = new MyObj;
            myObj.time = TimeToString(time[i],TIME_DATE);
            myObj.rent = rentPorTradeAcum;
            rentPorTradeAcumList.Add(myObj);
            
            if(lucroOp>=0){
               percPorTradeGainAcum = percPorTradeGainAcum + (lucroOp / (nAcoes * precoDeCompra));
            }else{
               percPorTradeLossAcum = percPorTradeLossAcum + (lucroOp / (nAcoes * precoDeCompra));
            }

            // ************************************************
            // Início: Cálculo do Drawdown máximo
            if ((lucroAcum+capitalInicial) > capMaxDD) {
               capMaxDD = lucroAcum + capitalInicial;
               capMinDD = capMaxDD;
            } else {
               if ((lucroAcum+capitalInicial) < capMinDD){
                  capMinDD = lucroAcum + capitalInicial;
                  rentDDMaxAux = (capMaxDD - capMinDD) / capMaxDD;
                  if (rentDDMaxAux > rentDDMax) {
                     rentDDMax = rentDDMaxAux;
                  }
               }
            }
            // Fim: Cálculo do Drawdown máximo
            // ************************************************
            
            nAcoes = 0;
            precoDeCompra = 0;
            comprado = false;
         } // fim do "if" da venda.
   } // fim do "if" do intervalo de tempo 
   } // fim do "for"
   
   
   double  dias = (t2-t1)/(60*60*24);
   double  anos = dias / 365.25;
   double meses = anos * 12;
   double rentTotal = 100.0*((lucroAcum+capitalInicial)/capitalInicial - 1);
   double rentMes = 100.0*(pow((1+rentTotal/100.0), 1/meses) - 1);

   string nome = Symbol();

   if(!jaCalculado){
      printf("Ativo: %s, Método: %s, Período: %s a %s", nome, nomeDoMetodo, TimeToString(t1,TIME_DATE|TIME_MINUTES|TIME_SECONDS), TimeToString(t2,TIME_DATE|TIME_MINUTES|TIME_SECONDS));
      printf("#Op: %d, #Pregoes: %d, Capital Inicial: %.2f", nOp, nPregoes, capitalInicial);
      printf("Somatório dos valores positivos: %.2f e negativos: %.2f e diferença: %.2f", acumPositivo, acumNegativo, acumPositivo+acumNegativo);      
      printf("lucro: %.2f, Capital Final: %.2f",  floor(lucroAcum), floor(capital));
      printf("#Acertos: %d (%.2f%%), #Erros: %d (%.2f%%)", nAcertos, 100.0*nAcertos/nOp,  nErros, 100.0*nErros/nOp);
      printf("Fração de pregões/candles posicionado: %.2f%%", 100.0*nPregoesPos/nPregoes);

      printf("#PregoesPosicionado: %d, #PregoesPosicionado/Op: %.2f", nPregoesPos, 1.0*nPregoesPos/nOp);

      if(reaplicar){
         printf("Rentabilidade Total: %.2f%%, #Meses: %.0f, #Op/mes: %.2f, Rentabilidade/Op: %.2f%%", rentTotal, meses, nOp/meses, rentMes/(nOp/meses));
      }else{
         printf("Rentabilidade Total: %.2f%%, #Meses: %.0f, #Op/mes: %.2f, Rentabilidade/Op: %.2f%%", rentTotal, meses, nOp/meses, rentTotal/nOp);
      }      
      
      if(reaplicar){
         printf("Rentabilidade Mensal (com reinvestimento do lucro): %.2f%% (juros compostos)", rentMes);
      }else{
         printf("Rentabilidade Mensal (sem reinvestimento do lucro): %.2f%% (juros simples)", rentTotal/meses);
      }  

      printf("Rentabilidade Média por Trade (calculada trade a trade): %.4f%%", 100 * rentPorTradeAcum / nOp);

      printf("Ganho Percentual Médio por Operação Gain: %.2f%%", 100*percPorTradeGainAcum/nAcertos);
      printf("Perda Percentual Média por Operação Loss: %.2f%%", 100*percPorTradeLossAcum/nErros);
      printf("Pay-off: %.2f, Razão G/R: %.2f, Drawdown Máximo: %.2f%%", -(percPorTradeGainAcum/nAcertos) / (percPorTradeLossAcum/nErros), -(percPorTradeGainAcum) / (percPorTradeLossAcum), 100.0 * rentDDMax);  
      //printf("Razão G/R: %.2f", -(percPorTradeGainAcum) / (percPorTradeLossAcum));
      //printf("Drawdown Máximo: %.2f%%", 100.0 * rentDDMax);
      
      printf("");
      
      
      // Há problemas de Memory Leak com relação às variáveis novas criadas para essa saída de dados
      /****************** Saída de Dados para Arquivo ***********************************/
      string s;
      //C:\Users\<o usuário windows>\AppData\Roaming\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\MQL5\Files
      int h = FileOpen("SrB_output.txt",FILE_WRITE|FILE_ANSI|FILE_TXT);
      if(h==INVALID_HANDLE){ Alert("SrB: Error opening file"); return 1;}
      MyObj *obj = new MyObj;
      for(int i = 0; i<rentPorTradeAcumList.Total(); i++){
         obj = rentPorTradeAcumList.GetNodeAtIndex(i);
         s = obj.time + "\t\t" + DoubleToString(obj.rent,2);
         FileWrite(h,s);
         //delete obj;
      }
      delete rentPorTradeAcumList;
      delete obj;
      FileClose(h);
      /****************** Saída de Dados para Arquivo ***********************************/
      
      //int n = rentPorTradeAcumList.Total();
      //for(int i = 0; i<n; i++){
      //   MyObj *obj = new MyObj;
      //   delete rentPorTradeAcumList.GetNodeAtIndex(i);
      //}
      //delete rentPorTradeAcumList;
      
   }
   jaCalculado = true;

   return(rates_total);
}




