"""Mapper 773's PRG banks and the MCU's FIFO on a py65 memory, for nesemu."""
from mknes import prg_banks

BANK_REG, BANK_LO, BANK_HI = 0x5010, 0x8000, 0xC000
FIFO_DATA, FIFO_STAT = 0x40F0, 0x40F1


class Cart:
    """$8000-$BFFF the bank BANK_REG maps, bank 0 the image; the image and $C000-$FFFF read only"""

    def __init__(self, mem, prg):
        self.mem = mem
        mem.write(BANK_LO, list(prg[:0x8000]))
        self.bank, self.banks = 0, prg_banks(prg)
        mem.subscribe_to_write([BANK_REG], self._switch)
        mem.subscribe_to_write(range(BANK_LO, BANK_HI), lambda a, v: mem._subject[a] if self.bank == 0 else None)
        mem.subscribe_to_write(range(BANK_HI, 0x10000), lambda a, v: mem._subject[a])
        self.mcu = None

    def _switch(self, a, v):
        s = self.mem._subject
        self.banks[self.bank] = s[BANK_LO:BANK_HI]
        s[BANK_LO:BANK_HI] = self.banks.get(v, [0xFF] * (BANK_HI - BANK_LO))
        self.bank = v

    def bank_bytes(self, bank, n):
        mem = self.mem._subject[BANK_LO:BANK_HI] if bank == self.bank else self.banks[bank]
        return bytes(mem[:n])

    def attach(self, mcu):
        """mcu behind the FIFO"""
        m, self.mcu = self.mem, mcu
        m.subscribe_to_write([FIFO_DATA], lambda a, v: self.mcu.rx(v))
        m.subscribe_to_read([FIFO_DATA], lambda a: self.mcu.tx.popleft() if self.mcu.tx else 0)
        m.subscribe_to_read([FIFO_STAT], lambda a: 0x00 if self.mcu.tx else 0x80)
