from scpi import KEYSIGHT_33600A
import asyncio, threading
import subprocess, os, signal
import time
import pandas as pd
from io import StringIO

class TestHandler: 
     
    def __init__(self):
        self.curr_file_path = None
        self.test = None
        self.available = {"enabled": True}
        self.unavailable = {"enabled": False}
        self.last_line = ""
        self.file = None
        self.reading = False
        self.abort = False
        pass
    
    async def start_test(self, fname, ptp_warm, clk_warm):
        self.available["enabled"] = False
        self.unavailable["enabled"] = True
        if self.test is None:
            if not os.path.exists("./nic_time_reader/data_reader.sh"):
                print("could not find path to shell script")
                print(f"Current working directory: {os.getcwd()}")
                return False
            script_path = os.path.abspath("./nic_time_reader/data_reader.sh")
            self.test = subprocess.Popen(["sudo", script_path, "-f", fname, "-p", str(ptp_warm), "-c", str(clk_warm)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
            self.curr_file_path = fname
            for _ in range(30):
                time.sleep(0.1)
                if os.path.exists(fname):
                    break
            if not os.path.exists(fname):
                print("Timeout while starting test")
                await self.stop_test()
                return False
            self.file = open(fname, "r")
            print("Test started")
            return True
        else:
            print("Test already in progress")
            return False

    async def stop_test(self):
        print("trying to stop test")

        if self.test is not None:
            self.test.terminate()
            self.test = None
            print("Killed a process")
        else:
            print("No processes to kill")

        if self.file is not None:
            self.file.close()
            self.file = None
            print("Closed file handle")
        else:
            print("No file handles to close")

        self.available["enabled"] = True
        self.unavailable["enabled"] = False

        print("stopped test")

    def read_continuous(self):
        while self.reading:
            self.read_line()
            time.sleep(0.1)

    def read_line(self):
        if self.file is None:
            return self.last_line
        
        line = self.file.readline().replace("\n", "")

        if len(line) == 0 or line == "\n":
            return self.last_line
        
        self.last_line = line
        return line

    def read_last_line(self):
        if self.curr_file_path is None:
            return ""

        return self.last_line

    async def start_manipulation_test(self, fname, ptp_warm, clk_warm, delay_handler, siggen: KEYSIGHT_33600A):
        if siggen is None or siggen.handle is None:
            return ["No siggen available", "negative"]
        
        delay_name = fname+"_delay.csv"

        if delay_handler.check_filename_availability(delay_name) is False:
            print(f"Filename {delay_name} already in delay data directory. Aborting.")
            return [f"Filename for delay data file taken. Please choose new filenames for a/the ptp process/es.", "negative"]
        
        if delay_handler.busy:
            return ["Delay Handler is already in operation, retry later", "negative"]
        
        if self.test is not None:
            return ["PTP already in progress. Wait or kill to start test", "negative"]
        
        delay_handler.busy = True

        self.reading = True
        reader = threading.Thread(target=self.read_continuous)

        async def abort():
            self.reading = False
            reader.join()

            await self.stop_test()

            self.last_line = ""

            delay_handler.busy = False

            self.abort = False
            return ["Aborted test", "warning"]
        
        async def cancel_group():
            while delay_handler.busy:
                if self.abort:
                    print("Cancelling async group")
                    self.abort = False
                    delay_handler.busy = False
                    raise Exception().add_note("Canceled async") 
                await asyncio.sleep(0.1)

        try:
            reader.start()

            print("starting test")
            if await self.start_test(f"./nic_time_reader/{fname}.csv", ptp_warm, clk_warm):
                while True:
                    if self.abort:
                        return await abort()

                    line = self.read_last_line()

                    if len(line) != 0:
                        phase = line.split(",")[0]
                        if phase != "1" and phase != "phase":
                            break

                    await asyncio.sleep(0.2)

                while True:
                    if self.abort:
                        return await abort()

                    line = self.read_last_line()

                    if len(line) != 0:
                        phase = line.split(",")[0]
                        if phase != "2" and phase != "phase":
                            break

                    await asyncio.sleep(0.2)

                delay_handler.busy = False
                async with asyncio.TaskGroup() as tg:
                    delay_task = tg.create_task(delay_handler.follow_delay_curve(siggen, delay_name))
                    cancel_task = tg.create_task(cancel_group())

                await self.stop_test()

                self.reading = False
                reader.join()

                self.last_line = ""

                return ["Successfully completed manipulation test", "positive"]
            else:
                delay_handler.busy = False
                return ["Something went wrong", "negative"]
        except Exception as e:
            self.reading = False
            reader.join()

            await self.stop_test()

            self.last_line = ""

            print(e)

            return [e.__str__(), "warning"]

class DelayHandler:

    eps = 1e-10

    in_seconds = {
        "d": 24*60*60,
        "h": 60*60,
        "m": 60,
        "s": 1,
        "ms": 1e-3,
        "us": 1e-6,
        "ns": 1e-9
    }

    def __init__(self):
        self.delay_correction = 0

        self.actionable_delay_curve = {}
        self.delay_curve = {}
        self.actions = []
        self.busy = False
        pass

    def check_filename_availability(self, name):
        if not os.path.isdir("./delay_data"):
            print("Could not find delay data folder. Aborting")
            return False
        
        if name in os.listdir("./delay_data"):
            return False
        
        return True

    async def follow_delay_curve(self, siggen: KEYSIGHT_33600A, filename: str = None):
        if self.busy:
            return
        self.busy = True

        if filename is not None and not os.path.isdir("./delay_data"):
            print("Could not find delay data folder. Aborting")
            self.busy = False
            return
        

        if filename is None:
            siggen.lock()

            try:
                for step in self.actions:
                    siggen.set_delay(step["delay"]+self.delay_correction)
                    await asyncio.sleep(step["wait"])
            except Exception as e:
                print(e)

            siggen.unlock()
        else:
            try: 
                f = open("./delay_data/"+filename, "w")

                f.write("time, delay\n")
            except Exception as e:
                try:
                    f.close()
                except:
                    pass
                print(e)
                print("Aborting")
                return

            siggen.lock()

            try:
                for step in self.actions:
                    siggen.set_delay(step["delay"]+self.delay_correction)
                    f.write(str(time.time())+", "+str(step["delay"])+"\n")
                    await asyncio.sleep(step["wait"])
            except Exception as e:
                print(e)
                print("Aborting")

            siggen.unlock()

            f.close()

        self.busy = False

    def get_delay_curve(self) -> tuple[list, list]:
        if not "timestamps" in self.delay_curve or not "delays" in self.delay_curve:
            return [], []

        return self.delay_curve["timestamps"], self.delay_curve["delays"]
    
    def get_actionable_delay_curve(self) -> tuple[list, list]:
        if not "timestamps" in self.actionable_delay_curve or not "delays" in self.actionable_delay_curve:
            return [], []

        return self.actionable_delay_curve["timestamps"], self.actionable_delay_curve["delays"]

    def compute_delay_curve(self, rows: list[dict]) -> None:
        if self.busy:
            print("Currently busy")
            return

        x_axis = []
        y_axis = []

        for row in rows:
            if row["duration"] == '':
                row["duration"] = 0
            if row["start"] == '':
                row["start"] = 0
            if row["stop"] == '':
                row["stop"] = 0

            dur_s = int(row["duration"])*self.in_seconds[row["duration_unit"]]
            init_s = int(row["start"])*self.in_seconds[row["start_unit"]]
            fin_s = int(row["stop"])*self.in_seconds[row["stop_unit"]]

            if len(x_axis) == 0:
                x_axis.append(0)
                x_axis.append(dur_s)
            else:
                x_axis.append(x_axis[-1])
                x_axis.append(x_axis[-1]+dur_s)

            y_axis.append(init_s)
            y_axis.append(fin_s)

        self.delay_curve.clear()
        self.delay_curve["timestamps"] = x_axis
        self.delay_curve["delays"] = y_axis
    
    def compute_actionable_delay_curve(self) -> None:
        if self.busy:
            print("currently busy")
            return

        timestamps, delays = self.get_delay_curve()

        waits = [] # Timestamp to wait times
        for i in range(len(timestamps)-1):
            waits.append(int(timestamps[i+1]-timestamps[i])) # Since we are manipulating a PPS Signal, we do not care about durations less than a second
        waits.append(0)

        action_delays = []
        action_wait = []
        for i in range(len(delays)-1):
            if waits[i] == 0: # 0 second time interval can be skipped
                continue

            if delays[i] == delays[i+1]: # Set delay and wait
                action_delays.append(delays[i])
                action_wait.append(waits[i])
            else:
                for j in range(int(waits[i])): # Set delay in 1 second increments (maximum 1s resolution since PPS Signal)
                    action_delays.append(delays[i]+(delays[i+1]-delays[i])/int(waits[i])*(j))
                    action_wait.append(1)

        # Add final point
        action_delays.append(delays[-1])
        action_wait.append(0)

        keep = [1 for i in action_delays]
        # Aggregate points of same delays
        for i in range(1,len(action_delays)):
            if abs(action_delays[i-1]-action_delays[i])<self.eps:
                keep[i] = 0
        action_delays = [action_delays[i] for i in range(len(keep)) if keep[i]]
        action_wait = [action_wait[i] for i in range(len(keep)) if keep[i]]

        self.actions.clear()
        for i in range(len(action_delays)):
            self.actions.append({"delay": action_delays[i], "wait": action_wait[i]})

        timestamps_from_wait = []
        for i in range(len(action_wait)):
            if i==0:
                timestamps_from_wait.append(0)
            else:
                timestamps_from_wait.append(timestamps_from_wait[i-1]+action_wait[i-1])

        self.actionable_delay_curve.clear()
        self.actionable_delay_curve["timestamps"] = timestamps_from_wait
        self.actionable_delay_curve["delays"] = action_delays
