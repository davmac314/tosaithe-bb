# TSBP bare bones kernel

This is an example "bare-bones" (i.e. almost absolutely minimal) kernel for use with a loader 
using the Tosaithe Boot Protocol (TSBP). It is intended only as an example of how to get
started.

The example "kernel" merely draws a three-colour "flag" on the screen (framebuffer), and then
goes into a dead loop.

It is x86-64 only. It should build on any recent Linux system with the system GCC and binutils.

To build:

- run "make"

To run (in qemu):

1. build Tosaithe and copy it, or copy a pre-built image, to `bootdisk/EFI/BOOT/BOOTX64.EFI` (i.e.
   rename it from `tosaithe.efi` to `BOOTX64.EFI`).

   Pre-build images are available from the Tosaithe releases page:

   https://github.com/davmac314/tosaithe/releases

   (Get the file named `tosaithe.efi`, don't forget to rename it and move/copy it to the right location).

2. You will need OVMF (UEFI implementation, part of EDK2) firmware files. These are normally
   distributed with QEMU, or some distributions as part of the "ovmf" package. Check the Makefile
   and change `QEMU_FW_BASEDIR` (or `OVMF_CODE_FILE` and `OVMF_VARS_FILE`) if necessary, or in
   case your distribution does not include them, you can get suitable pre-built files here:

   https://retrage.github.io/edk2-nightly/

   (eg `RELEASEX64_OVMF_CODE.fd` and `RELEASEX64_OVMF_DATA.fd`). Note that this is an external
   link with a separate maintainer, we are not responsible for them and cannot make guarantees
   of their integrity or suitability. If you prefer, you can build the files yourself; they are
   part of EDK2:

   https://github.com/tianocore/edk2

   (Build instructions are outside the scope of this document).

   Set the `OVMF_CODE_FILE` and `OVMF_VARS_FILE` variables in the Makefile to the correct
   locations after downloading or building these files.

3. run with "make run".

   The `bootdisk` directory will be emulated as a FAT filesystem by QEMU. The Tosaithe menu will
   be displayed with a single menu entry, allowing you to run the "kernel".

The following section briefly explains the code and build process.

## Walk-through

The source code can be found in `kernel.c`. The entry header is established via the following:

    static tosaithe_entry_header ts_entry_hdr __attribute__((section(".tsbp_hdr"), used)) = {
            'T' + ('S' << 8) + ('B' << 16) + ('P' << 24),
            0, // version
            0, // min. required loader version
            1, // flags - require framebuffer
            (uintptr_t)&KERNEL_STACK_TOP
    };

Note the use of `__attribute__((section(".tsbp_hdr"), used))` - this does two things:

1. Puts the entry header structure in the `.tsbp_hdr` section (we reference this in the linker
   script)
2. Ensures that the header is emitted even though it is not referenced elsewhere in the source.

The `KERNEL_STACK_TOP` is declared just above:

    struct opaque;
    
    extern struct opaque KERNEL_STACK_TOP;  // defined in linker script

By declaring it as a `struct` type with no definition for the struct, we prevent the variable from
being used in any way other than by taking its address (which will yield the value defined, as the
comment notes, by the linker script).

The entry point to the kernel is the `tsbp_entry` function (again, this is determined by the
linker script): 

    void tsbp_entry(tosaithe_loader_data *tosaithe_data)
    {
        ...

The code looks for framebuffer information and, if a suitable framebuffer is present, draws a
tricolor "flag" pattern on the screen. Finally, it ends with an infinite loop, using the "hlt"
instruction to avoid running the processor in a hot loop:

    while (1) {
        asm volatile ( "hlt\n" );
    }

Looking at the linker script, we see where the magic happens to make this kernel bootable with the
Tosaithe protocol. First, the segments are defined:

    PHDRS
    {
      text PT_LOAD FILEHDR PHDRS FLAGS(0x5) ; /* 0x5 = READ (0x4) + EXECUTE (0x1) */
      data PT_LOAD ;
      tsbp_hdr 0x64534250 ;
    }

Note that we choose to include the file header and program headers in the `text` segment (via the
`FILEHDR` and `PHDRS` directives). This isn't necessary, but if we didn't do this then we would
need to make sure that the segment is aligned to a page boundary as this is a requirement of TSBP,
which would mean adding padding and increasing the size of the kernel file (although reducing its
loaded size).

Since the headers are part of the segment, we allow for them in setting the first output location:

    . = SEGMENT_START("text-segment", 0xffffffff80200000) + SIZEOF_HEADERS;
 
Note that this kernel has a default starting address of `0xffffffff80200000` - that's 2MB past the
lowest allowed address. That would give us a guaranteed-usable portion of the address space (i.e.
the kernel might choose to map anything within that 2MB area) although we don't actually need that
for this example.

The rest just defines the output sections and specifies which segment they are output to. We put
all code (`.text` sections) and read-only data in the `text` segment, and everything else in the
`data` segment. This is a nice and simple arrangement, but it is not necessary and many variations
are possible. Importantly, all `.bss` (zero'd data) sections are placed at the end of the `data`
segment - this avoids the need for them to be stored in the kernel image, making it smaller. There
is some space allocated for a stack at the end of the BSS region:

    KERNEL_STACK_BOTTOM = .;
    . = . + 8192;
    KERNEL_STACK_TOP = .;

The `KERNEL_STACK_TOP` symbol is used in kernel.c to initialise part of the entry header
structure, which the bootloader reads to determine the stack top location.
