# I am developing 6502 program in wsl having an emulator which is able to step executing code instruction by instruction. It prints out pc and other registers and memory content in the debug mode. One thing to improve is when pc changes I would like see the jump in the list file to the pc showing disassembly and assembly code. In this way, while I am stepping instructions, I can see quickly see which part of code it is executing rather than scroll up and down the list file myself.

# This is my development envrionment.
# 1, 6502 emulator is written in c code and running in wsl
# 2 6502 emulator has all access to the pc, register and memory
# 3, vscode opens source code and list file in windows 11
# 4, 6502 emulator opens up LCD window as an IO device using SDL2

# what is your recommendation ?

# ==========================================================================================

# Alternative: Terminal-Based Solution
# If a VS Code extension is too complex, a simpler, though less integrated, approach is to write a script that displays the current instruction in the terminal.

# Modify Assembler: Generate a list file with addresses. For example: 0800 A9 05 LDA #$05.

# Modify Emulator: The emulator prints the current PC to standard output.

# Create a Shell Script: A shell script can be used to run the emulator and, using grep or awk, find the line in the list file that matches the current PC. The script can then display that single line to the terminal.
# ==========================================================================================

# can you write a python code doing the below

# 1, it takes in two files listFile and trace.log
# 2, the pc value is "85C5: " format in the trace.log as

# 8012: A9 11       LDA #$11
# CPU State: PC:8014 A:11 X:00 Y:00 SP:FD Status:24 (NV-B DIZC)
# RAM State: $0000:00 $0001:00 $0002:00 $0003:00
# RAM State: $6000:00 $6001:00 scroll mode $0264:00 row $0230:00 col $0231:00
# RAM State: $0300:00 $0301:00 $0302:00 $0303:00


# 3, given the latest pc, which is found at the bottom of trace.log, display the 30 lines of listFile centered at the pc
# 4, the format of listFile is the below and pc value is 822D  in 00:822D ...

#                              77: init_working_dir:
# 00:822D A900                78:      LDA #0                      ; Start at root directory
# 00:822F 8D1302              79:      STA WORKING_DIR_INODE
#                             80: 
#                             81:     ; LDA #'1' ; JSR print_char ; JSR print_char ; JSR print_char ; JSR print_char ; JSR print_char ; LDA #LCD_HOME ; J
#                             82: 
#                             83: keyinput_loop:
# 00:8232 207885              84:     JSR poll_keyboard
# 00:8235 90FB                85:     BCC keyinput_loop          ; No key yet, poll again
#                             86: 
#                             87:     ;; scroll up down - Check for arrow keys first
# 00:8237 C95B                88:     CMP #KEY_UP
# 00:8239 F026                89:     BEQ handle_key_up
# 00:823B C95D                90:     CMP #KEY_DOWN
# 00:823D F02D                91:     BEQ handle_key_down
#                             92:     
#                             93:     ;; scroll up down - Any other key exits scroll mode
# 00:823F 48                  94:     PHA                    ; Save the key value
# 00:8240 AD6402              95:     LDA SCROLL_MODE
# 00:8243 F003                96:     BEQ normal_key_processing_restore
#                             97: ;summer_break:
# 00:8245 20E582              98:     JSR exit_scroll_mode
#                             99: 

# 5, the format of trace.log is the below, where pc value is 8006 in 8006:

# 8006: 85 13       STA $13
# CPU State: PC:8008 A:C0 X:00 Y:00 SP:FD Status:A4 (NV-B DIZC)
# RAM State: $0000:00 $0001:00 $0002:00 $0003:00
# RAM State: $6000:00 $6001:00 scroll mode $0264:00 row $0230:00 col $0231:00
# RAM State: $0300:00 $0301:00 $0302:00 $0303:00

# ==========================================================================================

import sys
import re
import time
import os

# The original functions remain the same
def find_pc_in_trace(trace_file):
    """
    Finds the latest PC from the trace log.
    """
    pc_pattern = re.compile(r'CPU State: PC:([0-9A-Fa-f]{4})')
    last_pc = None
    
    with open(trace_file, 'r') as f:
        for line in f:
            match = pc_pattern.search(line)
            if match:
                last_pc = match.group(1).upper()
                
    if last_pc:
        return last_pc
    
    pc_pattern_alt = re.compile(r'^([0-9A-Fa-f]{4}):')
    
    with open(trace_file, 'r') as f:
        for line in reversed(list(f)):
            match = pc_pattern_alt.match(line)
            if match:
                return match.group(1).upper()
    
    return None

def find_line_by_pc(list_file, pc_value):
    """
    Finds the line number in the list file.
    """
    line_pattern = re.compile(r'^[0-9A-Fa-f]{2}:' + pc_value)
    
    with open(list_file, 'r') as f:
        for i, line in enumerate(f, 1):
            if line_pattern.match(line):
                return i
    return None

def display_centered_lines(list_file, start_line, num_lines):
    """
    Prints a block of lines from a file, centered around a given line.
    """
    try:
        with open(list_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: {list_file} not found.")
        return

    total_lines = len(lines)
    half_lines = num_lines // 2
    
    start_index = max(0, start_line - 1 - half_lines)
    end_index = min(total_lines, start_line - 1 + half_lines + 1)
    
    if end_index - start_index < num_lines:
        if start_index == 0:
            end_index = min(total_lines, num_lines)
        else:
            start_index = max(0, end_index - num_lines)
            
    # Clear the terminal before displaying the new output
    os.system('cls' if os.name == 'nt' else 'clear')

    for i in range(start_index, end_index):
        if i == start_line - 1:
            print(f'-> {lines[i].strip()}')
        else:
            print(f'   {lines[i].strip()}')

# New main loop for continuous monitoring
def main():
    if len(sys.argv) != 3:
        print("Usage: python3 debugger.py <list_file> <trace_log>")
        sys.exit(1)

    list_file_path = sys.argv[1]
    trace_log_path = sys.argv[2]
    
    last_known_size = 0
    
    print("Starting live debugger. Press Ctrl+C to exit.")
    
    try:
        while True:
            # Check for file size changes
            current_size = os.path.getsize(trace_log_path)
            
            if current_size > last_known_size:
                last_known_size = current_size
                
                # 1. Get the latest PC from the trace log
                latest_pc = find_pc_in_trace(trace_log_path)
                if not latest_pc:
                    time.sleep(0.1)
                    continue

                # 2. Find the corresponding line in the list file
                target_line = find_line_by_pc(list_file_path, latest_pc)
                if not target_line:
                    time.sleep(0.1)
                    continue

                # 3. Display 30 lines centered on the target line
                display_centered_lines(list_file_path, target_line, 50)
                
            time.sleep(0.1) # Check for new data every 100ms
    
    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nLive debugger stopped.")
        sys.exit(0)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
