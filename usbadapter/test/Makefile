CFLAGS = -std=c11 -Wall -Wextra -Werror -I../src

test: test_keymap test_mouse
	./test_keymap
	./test_mouse

test_keymap: test_keymap.c ../src/keymap.c ../src/keymap.h ../src/kbdword.h
	$(CC) $(CFLAGS) -o $@ test_keymap.c ../src/keymap.c

test_mouse: test_mouse.c ../src/mouse.c ../src/mouse.h
	$(CC) $(CFLAGS) -o $@ test_mouse.c ../src/mouse.c

clean:
	rm -f test_keymap test_mouse

.PHONY: test clean
