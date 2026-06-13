// Minimal PE probe for Wine #29384 (VirtualProtect COW on file-backed .text).
// Build: scripts/fixtures/wine_gap/build_cow_probe.sh
// Run:   arch -x86_64 "$WINE" cow_probe.exe  (Gcenx Wine is x86_64 on macOS)
//
// Exit 0 = private .text patch survived VirtualProtect back to RX (bug fixed).
// Exit 2 = patch reverted (COW lost — mod loaders like SKSE/F4SE may break).
#include <stdio.h>
#include <windows.h>

__declspec(noinline) static int probe_target(void) {
    return 0xA5A5A5A5;
}

int main(void) {
    unsigned char *code = (unsigned char *)(void *)&probe_target;
    DWORD old_prot = 0;
    unsigned char original = *code;
    unsigned char after;

    if (!VirtualProtect(code, 4096, PAGE_EXECUTE_READWRITE, &old_prot)) {
        fprintf(stderr, "cow_probe: VirtualProtect(RWX) failed err=%lu\n", (unsigned long)GetLastError());
        return 1;
    }

    *code = 0x90; /* NOP over first byte of probe_target */

    if (!VirtualProtect(code, 4096, PAGE_EXECUTE_READ, &old_prot)) {
        fprintf(stderr, "cow_probe: VirtualProtect(RX) failed err=%lu\n", (unsigned long)GetLastError());
        return 1;
    }

    after = *code;
    if (after != 0x90) {
        printf("cow_probe: FAIL cow_lost original=0x%02x after=0x%02x (Wine #29384)\n",
               (unsigned)original, (unsigned)after);
        return 2;
    }

    printf("cow_probe: PASS cow_preserved (Wine #29384 mitigated on this build)\n");
    return 0;
}
