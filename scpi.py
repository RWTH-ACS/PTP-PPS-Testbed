import pyvisa
import time

class SCPI():

    def __init__(self, rm, address, port=5025):
        self.rm = rm
        self.address = address
        self.port = port
        self.handle = None

        self.locked = False

    def open(self):
        if self.handle is None:
            self.handle = self.rm.open_resource(f"TCPIP::{self.address}::{self.port}::SOCKET",
                                                 write_termination='\n', 
                                                 read_termination='\n')
    
    def close(self):
        if self.handle is not None:
            self.handle.close()
            self.handle = None

    def wait_lock(self):
        while self.locked:
            time.sleep(0.01)

    def lock(self):
        self.wait_lock()
        self.locked = True

    def unlock(self):
        self.locked = False

class KEYSIGHT_33600A(SCPI):
    
    def __init__(self, rm, address, port=5025, signal_level=3.3):
        super().__init__(rm, address, port)
        self.signal_level = signal_level
        self.delay_correction = 0

    def open(self):
        if self.handle is None:
            super().open()
            self.set_up(self.signal_level)

    def change_address(self, address):
        if self.handle is None:
            self.address = address
            return True
        else:
            print("Cannot change address while connected")
            return False

    def set_up(self, signal_level):
        self.lock()
        # set up the pps output on the first channel
        self.handle.write("SOUR1:FUNC PULS")
        self.handle.write("SOUR1:FUNC:PULS:TRAN:LEAD 2.9E-9")
        self.handle.write("SOUR1:FUNC:PULS:TRAN:TRA 2.9E-9")
        self.handle.write("SOUR1:FUNC:PULS:WIDT 1E-5 s")
        self.handle.write("SOUR1:FREQ 50 kHz") # Frequency must be higher than 1Hz to ensure a Pulse is triggered on every Signal
        self.handle.write("SOUR1:OUTP:LOAD INF")
        self.handle.write(f"SOUR1:VOLT:HIGH +{signal_level}")
        self.handle.write(f"SOUR1:VOLT:LOW +0")
        self.handle.write("SOUR1:BURS:MODE TRIG")
        self.handle.write("SOUR1:BURS:NCYC 1")
        self.handle.write("SOUR1:BURS:PHAS 0")
        self.handle.write("SOUR1:BURS:STAT ON")

        # set up 10 MHz on second channel
        self.handle.write("SOUR2:FUNC SIN")
        self.handle.write("SOUR2:FREQ 10 MHz")
        self.handle.write("SOUR2:OUTP:LOAD INF")
        self.handle.write("SOUR2:BURS:MODE TRIG")
        self.handle.write("SOUR2:BURS:NCYC INF")
        self.handle.write("SOUR2:BURS:PHAS 0")
        self.handle.write("SOUR2:VOLT 1 Vrms")
        self.handle.write("SOUR2:BURS:STAT ON")

        # set up the trigger on external pps signal
        self.handle.write("TRIG:SOUR EXT")
        self.handle.write("TRIG:SLOP POS")
        self.handle.write(f"TRIG:LEV {signal_level/2}")
        self.handle.write(f"TRIG:DEL {self.delay_correction}")

        # enable outputs
        self.handle.write("OUTP 1")
        self.handle.write("OUTP 2")

        self.unlock()

    def set_phase(self, phase_angle): # Only use when locked!
        self.handle.write(f"BURS:PHAS {phase_angle} DEG")

    def set_delay(self, delay):
        self.handle.write(f"TRIG:DEL {delay}")
    