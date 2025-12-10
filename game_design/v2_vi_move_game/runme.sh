cat prev.a.out
\rm a.out
../../tools/vasm/vasm6502_oldstyle -L ./listFile -Fbin -dotdir ./hello.s
ls -al a.out
ls -al a.out > prev.a.out
#hexdump -C a.out
