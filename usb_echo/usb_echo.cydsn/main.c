/* ========================================
 *
 * Copyright YOUR COMPANY, THE YEAR
 * All Rights Reserved
 * UNPUBLISHED, LICENSED SOFTWARE.
 *
 * CONFIDENTIAL AND PROPRIETARY INFORMATION
 * WHICH IS THE PROPERTY OF your company.
 *
 * ========================================
*/
#include <project.h>
#include <string.h>
#include <stdlib.h>
#include <CyLib.h>

//#include <device.h>
uint8 buffer[512];
uint8 cmd, cmd_motornum, cmd_keywrd, cmd_sign, cmd_val;
uint8 inst_byte_out, val_byte_out;
uint16 length;
int number, repeats = 0, num_lines, current_line_num;
uint8 receiving, parsing;
uint8 lines[10][512];
int cmd_eval_val;
uint8 state = 0;
#define COMMAND 0
#define ARG1    1
#define KEYWORD 2
#define ARG2    3
#define SND8051 4
#define EVAL    5

///////////////////////////////////////////////////////
const char *byte_to_binary(int x)
{
    static char b[9];
    b[0] = '\0';

    int z;
    for (z = 128; z > 0; z >>= 1)
    {
        strcat(b, ((x & z) == z) ? "1" : "0");
    }

    return b;
}
////////////////////////////////////////////////////////

//serial receive ISR
CY_ISR(RX_INT){
    int RxData = UART_ReadRxData();
    //*debug*/ for (int i=0;i<strlen(byte_to_binary(RxData));i++){LCD_PutChar(byte_to_binary(RxData)[i]);}
    //if we hear back from the R31JP, that means there is an error
    //here, I am decoding the error code
    uint8 errorMsg[512];
    switch((int)RxData){
    case 0b10: strcpy(errorMsg, "POSITION CONTROL UNAVAILABLE\n\r");
        break;
    case 0b11: strcpy(errorMsg, "SPEED CONTROL UNAVAILABLE\n\r");
        break;
    case 0b01: strcpy(errorMsg, "NO SUCH MOTOR ERROR\n\r");
        break;
    case 0b00: sprintf(errorMsg, "Success! data was delivered to the R31JP, %d", RxData);
    }
    uint16 errLength = strlen(errorMsg);
    USB_LoadInEP(1, errorMsg, errLength); 
}

int main()
{
    CyGlobalIntEnable; /* Enable global interrupts. */
    
    // SET UP SERIAL COMMUNICATION (WITH R31JP)
    LCD_Start();					    // initialize lcd
	LCD_ClearDisplay();
    //CyGlobalIntEnable;
    rx_int_StartEx(RX_INT);             // start RX interrupt (look for CY_ISR with RX_INT address)
                                        // for code that writes received bytes to LCD.
    
    UART_Start();                       // initialize UART
    UART_ClearRxBuffer();
    
    // SET UP USB COMMUNICATION (WITH COMPUTER)
    USB_Start(0, USB_3V_OPERATION); // Start the USB peripheral
    while(!USB_GetConfiguration()); // Wait until USB is configured
    USB_EnableOutEP(2); // Enable our output endpoint (EP2);
    
    // LOOP ON THIS FOREVER
    for(;;)
    {
        //strcpy(buffer,"");
        parsing = 1;
        /*TODO:: FIRST WE NEED TO SAVE*** all the lines into lines after receiving them via USB*/
        if (!repeats || receiving){
            while(USB_GetEPState(2) == USB_OUT_BUFFER_EMPTY);   // Wait until we have data
            length = USB_GetEPCount(2);                         // Get the length of received data
            USB_ReadOutEP(2, buffer, length);                   // Get the data
            
            while(USB_GetEPState(1) != USB_IN_BUFFER_EMPTY);    // Wait until our IN EP is empty
            //if we are receiving the lines to be repeated, save the line
            if (receiving) strcpy(lines[current_line_num], buffer);
            /*debug*/LCD_PutChar('E');
        } else {
            /*debug*/LCD_PutChar('R');
            strcpy(buffer, lines[current_line_num]);
        }
        LCD_ClearDisplay();
        /*debug*/ for (int i=0;i<length-2;i++){LCD_PutChar(buffer[i]);}
        uint8 line[512] = "";
        //strcpy(line, buffer);
        char* word;
        word = strtok(buffer, " \n\r");
        while (word != NULL && parsing){
            switch(state){
            case COMMAND:
                state = ARG1;
                if      (strcmp(word, "motor") == 0)  cmd = 'm';
                else if (strcmp(word, "repeat") == 0) cmd = 'r';
                else if (strcmp(word, "delay")  == 0) cmd = 'd';
                else{
                    state = COMMAND;
                    //strcpy(line, "Parse Error: UNKNOWN COMMAND");
                    sprintf(line, "Parse Error: UNKNOWN COMMAND");
                    /*length = strlen(line);
                    USB_LoadInEP(1, line, length);*/
                    parsing = 0;
                }
                //*debug*/LCD_PutChar(cmd);
                break;
            case ARG1:{
                int arg1 = atoi(word);
                if (cmd == 'm' && arg1 != 0 && arg1 < 9){
                    state = KEYWORD;
                    cmd_motornum = arg1;
                } else if (cmd == 'd' || cmd == 'r'){
                    state = (cmd=='d')? EVAL : ARG2;
                    cmd_eval_val = arg1;
                }
                else {
                    state = COMMAND;
                    strcpy(line, "Parse Error: INVALID ARGUMENT");
                    /*length = strlen(line);
                    USB_LoadInEP(1, line, length);*/
                    parsing = 0;
                }
                break;}
            case KEYWORD:{
                state = ARG2;
                //*debug*/ for (int i=0;i<strlen(word);i++){LCD_PutChar(word[i]);}
                if (strcmp(word, "spd") == 0)      cmd_keywrd = 's';
                else if (strcmp(word, "pos") == 0) cmd_keywrd = 'p';
                else if (strcmp(word, "stop") == 0) {
                    cmd_keywrd = 's';
                    cmd_val = 0;
                    state = SND8051;
                }
                else{
                    state = COMMAND;
                    //sprintf(line, "Parse Error: UNKNOWN KEYWORD: %s", word);
                    sprintf(line, "Parse Error: UNKNOWN KEYWORD: %s", word);
                    /*length = strlen(line);
                    USB_LoadInEP(1, line, length);*/
                    parsing = 0;
                }
                break;}
            case ARG2:{
                /*int*/ number = abs(atoi(word));
                /*debug*/ for (int i=0;i<strlen(word);i++){LCD_PutChar(word[i]);}
                //check if the value is a number and if it is within bounds
                if (cmd == 'r' && number != 0 && word[0] != '-'){
                    state = EVAL;
                    cmd_val = number;
                }
                else if (cmd == 'm' && number != 0 && number <= 100 ){/*&& 
                    ((strlen(word) <= 3 && word[0] != '-') || (strlen(word)<=4 && word[0] == '-'))){*/
                    //append to the line the correct sign
                    state = SND8051;
                    cmd_sign = (word[0] == '-')? '-':'+';
                    cmd_val  = number;
                } else {
                    /*THINGS ARE ENDING UP HERE WHEN THEY ARE VALID AND SHOULD BE FINE*/
                    state = COMMAND;
                    sprintf(line, "Parse Error: INVALID VALUE: %d", number);
                    /*length = strlen(line);
                    USB_LoadInEP(1, line, length);*/
                    parsing = 0;
                }
                break;}
            }
            word = strtok(NULL, " \n\r");
        }
        
        //once done parsing a line, start processing and forwarding the data
        switch (state){
        case SND8051:{
                //======= INSTRUCTION BYTE ========
                //set the highest order bit to 1 to represent that this is the inst byte
                inst_byte_out = 1;   inst_byte_out = inst_byte_out << 3;
                //send over one bit that communicates whether to control position or speed
                // 1 is speed and 0 is position control and update byte out to include the keyword
                inst_byte_out += (cmd_keywrd == 's');    inst_byte_out = inst_byte_out << 1;
                //we need to also send over the direction of motion if we are controlling speed
                inst_byte_out += (cmd_sign == '+');      inst_byte_out = inst_byte_out << 1;
                //convert the motor number to binary and update the byte_out to include the motor number data
                uint8 motorNum = cmd_motornum-1;        //to zero-index
                inst_byte_out += (motorNum >> 2) & 1;             inst_byte_out = inst_byte_out << 1;
                inst_byte_out += (motorNum >> 1) & 1;             inst_byte_out = inst_byte_out << 1;
                inst_byte_out += (motorNum >> 0) & 1;
                
                //======= VALUE BYTE ========
                //set the highest order bit to 0 to represent that this is the value byte
                val_byte_out = 0;   
                //convert the desired value of speed or position to binary
                uint8 value = cmd_val;
                for (int i = 6; i>=0; i--){
                    val_byte_out = val_byte_out << 1;
                    val_byte_out += (value >> i) & 1;
                }

                sprintf(line, "Success! Data being sent right over. line=%d numlines=%d", current_line_num, num_lines);
                //length = strlen(line);
                //Communicate this command byte to the R31JP
                UART_PutChar(val_byte_out);
                CyDelay(100);
                UART_PutChar(inst_byte_out);
                //in the case of repeats, make the appropriate
                if (repeats) {
                    current_line_num ++;
                }//sprintf(line, "linenum= %d, was saved as: %s", current_line_num-1, lines[current_line_num-1]);}
                if (repeats && current_line_num == num_lines){ 
                    current_line_num = 0;
                    repeats --;
                    receiving = 0;
                    //*debug*/LCD_PutChar('setup');
                }
                //*debug*/ for (int i=0;i<strlen(byte_to_binary(val_byte_out));i++){LCD_PutChar(byte_to_binary(inst_byte_out)[i]);}
                //update the state of the state machine to accept more commands
                state = COMMAND;
                break;}
            case EVAL:{
                //here we need to evaluate delays and repeats
                if (cmd =='d') CyDelay(cmd_eval_val);
                else if (cmd == 'r') {
                    /*DEAL WITH REPEATS HERE ::TODO*/
                    repeats = cmd_eval_val;
                    num_lines = cmd_val;
                    current_line_num = 0;
                    receiving = 1;
                    //*debug*/LCD_PutChar('R');
                }
                state = COMMAND;
                //sprintf(line, "numlines=%d, currentline=%d, receiving=%d",num_lines,current_line_num,receiving);
                sprintf(line, "Success! This command: %c, was evaluated in the PSoC.\n\r", cmd);
                break;}
            }
        length = strlen(line);
        USB_LoadInEP(1, line, length);                    // Echo the data back into the buffer
    
    }
}
