CC = gcc 
CCFLAGS = -Os -march=x86-64 -mcmodel=kernel -mno-red-zone -mgeneral-regs-only -fno-pie -fno-stack-protector -fno-stack-check -ffreestanding
CPPFLAGS =

# OVMF firmware location. See the README. There are two files: code and "vars", which is used as
# a template for the "OVMF-VARS.fd" file which will be used to emulate non-volatile storage.
# The files should be distributed with QEMU, but some distributions may not do so.
QEMU_FW_BASEDIR = /usr/share/qemu
OVMF_CODE_FILE := $(QEMU_FW_BASEDIR)/edk2-x86_64-code.fd
OVMF_VARS_FILE := $(QEMU_FW_BASEDIR)/edk2-i386-vars.fd

# For Debian/Ubuntu, install "ovmf" package and use the following:
#OVMF_CODE_FILE := /usr/share/OVMF/OVMF_CODE_4M.fd
#OVMF_VARS_FILE := /usr/share/OVMF/OVMF_VARS_4M.fd

all: kernel.elf

KERNEL_OBJECTS=kernel.o

kernel.elf: $(KERNEL_OBJECTS) link-script.lds
	$(LD) -Map kernel.elf.map -e tsbp_entry -T link-script.lds -o kernel.elf \
	    $(KERNEL_OBJECTS)

run: kernel.elf
	if [ ! -e $(OVMF_CODE_FILE) ]; then \
	    echo "OVMF not found. You must have OVMF firmware available, see README."; \
	    exit 1; \
	fi
	# Non-volatile storage for firmware:
	if [ ! -e OVMF-VARS.fd ]; then \
	    cp $(OVMF_VARS_FILE) OVMF-VARS.fd; \
	fi
	cp kernel.elf bootdisk
	qemu-system-x86_64 \
	    -drive if=pflash,format=raw,unit=0,file=$(OVMF_CODE_FILE),readonly=on \
	    -drive if=pflash,format=raw,unit=1,file=OVMF-VARS.fd \
	    -net none  \
	    -drive file=fat:rw:bootdisk,media=disk,format=raw

$(KERNEL_OBJECTS): %.o: %.c
	$(CC) $(CPPFLAGS) $(CCFLAGS) -c $< -o $@

$(KERNEL_OBJECTS:.o=.d): %.d: %.c
	$(CC) $(CPPFLAGS) -MM -MP -MG -MF $@ $<

clean:
	rm -rf kernel.elf $(KERNEL_OBJECTS) *.d

include $(KERNEL_OBJECTS:.o=.d)
