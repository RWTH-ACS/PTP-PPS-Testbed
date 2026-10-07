from nicegui import ui, app, events, background_tasks, Client, binding
import asyncio, os, tempfile, time
from matplotlib import pyplot as plt
from scpi import KEYSIGHT_33600A
from handlers import DelayHandler, TestHandler
import pyvisa
import re
import json

class DelayGraph:

    def __init__(self, size: tuple | None = None):
        self.size = size
        self.plot_obj = None
        self.ax = None
        
        pass

    def build(self, parent_slot):
        if self.plot_obj is None:
            with parent_slot:
                self.plot_obj = ui.matplotlib(figsize=self.size)
        else:
            print("Graph is already built!")

    def clear(self):
        if self.plot_obj is not None:
            self.ax = None
            self.plot_obj.figure.clear()
        else:
            print("Graph needs to be built before it can be cleared")

    def plot(self, x_axis: list, y_axis: list, style: str, name: str):
        if self.plot_obj is None:
            print("Graph needs to be built before plotting a curve")
            return
        if self.ax is None:
            self.ax = self.plot_obj.figure.gca()
            self.ax.set_xlabel("time in seconds")
            self.ax.set_ylabel("delay in seconds")

        self.ax.plot(x_axis, y_axis, style, label=name)
        self.ax.legend()

    def update(self):
        self.plot_obj.update()

class ConfigTable:

    def __init__(self, columns, empty_entry, column_units):
        self.columns = columns
        self.empty_entry = empty_entry
        self.column_units = column_units
        self.events = []
        self.enabled = {"enabled": True}

        self.configure()

        app.storage.general["config_rows"] = [self.empty_entry]

    def register_event(self, event):
        self.events = self.events + [event]

    def get_rows(self):
        #self.update()
        return self.config_table.rows

    def update(self):
        if len(self.events) != 0:
            for event in self.events:
                try:
                    event()
                except Exception as e:
                    print(e)

    def table_entry_edit(self, e: events.GenericEventArguments) -> None:
        row_id, colum_name, new_value = e.args

        for row in self.config_table.rows:
            if row['id'] == row_id:
                row[colum_name] = new_value

        app.storage.general["config_rows"] = self.config_table.rows

        if len(self.events) != 0:
            for event in self.events:
                try:
                    event()
                except Exception as e:
                    print(e)

    def table_option_used(self, e: events.GenericEventArguments) -> None:
        row_id, action = e.args

        if action == "up":
            if row_id == 0:
                return

            currRow = None
            prevRow = None
            for row in self.config_table.rows:
                if row['id'] == row_id:
                    currRow = row
                elif row['id'] == row_id-1:
                    prevRow = row

            prevRow['id'] = row_id
            currRow['id'] = row_id-1
        elif action == "down":
            currRow = None
            nextRow = None
            for row in self.config_table.rows:
                if row['id'] == row_id:
                    currRow = row
                if row['id'] == row_id+1:
                    nextRow = row
            
            if nextRow is None:
                return
            
            currRow['id'] = row_id + 1
            nextRow['id'] = row_id
        elif action == "delete":
            if len(self.config_table.rows) == 1:
                return
            
            for i in range(len(self.config_table.rows)):
                if self.config_table.rows[i]['id'] == row_id:
                    self.config_table.rows.pop(i)
                    break

            for row in self.config_table.rows:
                if row['id'] > row_id:
                    row['id'] = row['id'] - 1
        elif action == "add":
            for row in self.config_table.rows:
                if row['id'] > row_id:
                    row['id'] = row['id'] + 1

            new_entry = self.empty_entry.copy()
            new_entry['id'] = row_id+1

            self.config_table.rows.append(new_entry)

        self.config_table.rows.sort(key=lambda e: e['id'])

        app.storage.general["config_rows"] = self.config_table.rows
        
        if len(self.events) != 0:
            for event in self.events:
                try:
                    event()
                except Exception as e:
                    print(e)

    def configure(self):
        self.configured = False
        for col in self.columns:
            if col["name"].find("options") != -1 or col["name"].find("unit") != -1:
                table_configured = True
                break
        
        if not self.configured:
            self.columns.insert(0, {'name': 'options1', 'label': '', 'field': 'options1'})
            self.columns.append({'name': 'options2', 'label': '', 'field': 'options2'})

            index = 0
            for col in self.columns:
                if col['name'].find('options') == -1 and col['name'].find('unit') == -1:
                    self.columns.insert(index+1, {'name': col['name']+"_unit", 'label': '', 'field': col['field']+"_unit"})
                    self.empty_entry[col['name']+"_unit"] = self.column_units[col["name"]]["initial"]
                index = index+1

    def build(self, parent_slot):
        with parent_slot:
            self.config_table = ui.table(rows=app.storage.general["config_rows"], columns=self.columns, row_key='name')

        for column in self.columns:
            if column['name'].find('options') != -1:
                continue
            with self.config_table.add_slot(f"body-cell-{column['name']}"):
                with self.config_table.cell(column['name']):
                    if column['name'].find('unit') == -1:
                        ui.number().props(f':model-value=props.row.{column["name"]} dense').on(
                        'update:model-value',
                        js_handler='(e) => emit(props.row.id, props.col.name, e)',
                        handler=self.table_entry_edit
                        ).classes('w-20').bind_enabled(self.enabled)
                    else:
                        ui.select(self.column_units[column['name'].replace("_unit", "")]['options']).props(f':model-value=props.row.{column["name"]} dense').on(
                            'update:model-value',
                            js_handler='(e) => emit(props.row.id, props.col.name, e.label)',
                            handler=self.table_entry_edit
                        ).bind_enabled(self.enabled)

        with self.config_table.add_slot("body-cell-options1"):
            with self.config_table.cell("options1"):
                with ui.column():
                        ui.button(icon="arrow_drop_up").on(
                            "click",
                            js_handler='() => emit(props.row.id, "up")',
                            handler=self.table_option_used
                        ).props('dense').bind_enabled(self.enabled)
                        ui.button(icon="arrow_drop_down").on(
                            "click",
                            js_handler='() => emit(props.row.id, "down")',
                            handler=self.table_option_used
                        ).props('dense').bind_enabled(self.enabled)

        with self.config_table.add_slot("body-cell-options2"):
            with self.config_table.cell("options2"):
                with ui.column():
                    ui.button(icon="close").props("color=negative").on(
                        "click",
                        js_handler='() => emit(props.row.id, "delete")',
                        handler=self.table_option_used
                    ).props('dense').bind_enabled(self.enabled)
                    ui.button(icon="add").props("color=positive").on(
                        "click",
                        js_handler='() => emit(props.row.id, "add")',
                        handler=self.table_option_used
                    ).props('dense').bind_enabled(self.enabled)

class MainPage: # fix -> timer should update via timesteps, timer should not show negative values

    config_table_cols =  [
        {'name': 'start', 'label': 'Start', 'field': 'start'},
        {'name': 'stop', 'label': 'Stop', 'field': 'stop'},
        {'name': 'duration', 'label': 'Duration', 'field': 'duration'}
    ]
    config_table_empty_entry = {'id': 0, 'start': 0, 'stop': 0, 'duration': 0}
    config_table_column_units = {
        'start': {'initial': 'ms', 'options': ["s", "ms", "us", "ns"]},
        'stop': {'initial': 'ms', 'options': ["s", "ms", "us", "ns"]},
        'duration': {'initial': 's', 'options': ["d", "h", "m", "s"]}
    }

    def __init__(self, delay_handler: DelayHandler, waveform_generator: KEYSIGHT_33600A, test_handler: TestHandler, out_buf_lines=20):
        self.config_table = ConfigTable(self.config_table_cols, self.config_table_empty_entry, self.config_table_column_units)
        self.config_table.register_event(self.compute_graph_handler)

        self.delay_handler = delay_handler

        self.waveform_generator = waveform_generator

        self.test_handler = test_handler

        self.out_buf_lines = out_buf_lines

        self.timestamps = []
        self.delays = []
        self.action_timestamps = []
        self.action_delays = []

        self.times = {"ptp_init": 120, "phc_warm": 120}
        self.timer = {"text": "no test in progress", "time": 0, "time_str": "0s", "last_edit": time.time(), "locked": False, "phase": 0}

        self.outfile_var_devices = ["osa5422", "cm-ptp-1", "osa5404", "cm-ptp-2"]
        self.outfile_var_types = "ts,offset_min,offset_max,offset_max_abs,offset_mean,offset_rms,offset_stddev,freq_min,freq_max,freq_max_abs,freq_mean,freq_rms,freq_stddev,delay_min,delay_max,delay_max_abs,delay_mean,delay_rms,delay_stddev,delay_enabled".split(",")
        self.outfile_vars = ["phase", "timestamp_ns"]
        for dev in self.outfile_var_devices:
            self.outfile_vars = self.outfile_vars + [dev, dev+"_ts"]
        for dev in self.outfile_var_devices:
            for type in self.outfile_var_types:
                self.outfile_vars.append("ptp4l_"+dev+"_"+type)

        self.state = {}
        self.state_str = {}
        for var in self.outfile_vars:
            self.state[var] = 0.0
            self.state_str[var] = f"{0:.4f}"

    def update_outputs(self):
        text = self.test_handler.read_last_line()

        if len(text) == 0:
            self.state["phase"]=0
            return
        if text.find("phase")!=-1:
            return
        
        vars = text.split(",")

        for i in range(len(self.outfile_vars)):
            if len(vars[i])==0:
                self.state[self.outfile_vars[i]]=0.0
                self.state_str[self.outfile_vars[i]]=f"{0:.4f}"
            else:
                self.state[self.outfile_vars[i]]=float(vars[i])
                self.state_str[self.outfile_vars[i]]=f"{float(vars[i]):.4f}"

    def connect_btn_handler(self):
        try:
            if self.waveform_generator.change_address(self.ip_address_input.value):
                self.waveform_generator.open()            
                ui.notify("Connected", type="positive")
            else:
                ui.notify("Connection already open", type="warning")
        except Exception as e:
            ui.notify(e.args, type="negative")

    async def test_btn_handler(self):
        if self.waveform_generator is None:
            ui.notify("Not connected to waveform generator", type="negative")
            return
        ui.notify("Test started")
        await self.delay_handler.follow_delay_curve(self.waveform_generator)
        ui.notify("Test finished")

    def compute_graph_handler(self) -> None:
        self.delay_handler.compute_delay_curve(self.config_table.get_rows())
        self.delay_handler.compute_actionable_delay_curve()

        self.timestamps, self.delays = self.delay_handler.get_delay_curve()
        self.action_timestamps, self.action_delays = self.delay_handler.get_actionable_delay_curve()

    def update_graph(self, delay_graph: DelayGraph):
        delay_graph.clear()
        delay_graph.plot(self.timestamps, self.delays, "o-", "Table Defined Curve")
        delay_graph.plot(self.action_timestamps, self.action_delays, '.', "Planned Delays")
        delay_graph.update()

    async def save_config_btn_handler(self):
        name = await self.save_config_dialog.open()

        if name is None or len(name)==0:
            return

        config = self.config_table.get_rows()

        if not os.path.isdir("/home/usr/devel/ptp-test-platform/configs"):
            ui.notify("Could not find config directory", type="negative")
            return

        with open(f"/home/usr/devel/ptp-test-platform/configs/{name}", mode="w") as f:
            json.dump(config, f)

        self.name_input.value = ''

    def check_filename_validity(self, name):
        disallowed = r".*[<>:/\\|?*\".]|[\0-\31]"
        if re.match(disallowed, name) is not None:
            return "Name contains unsupported character"
        return None

    def config_name_validation(self, value):
        if value in os.listdir("./configs"):
            return "Name already taken"
        if len(value) == 0:
            return "Name needs at least 1 character"
        return self.check_filename_validity(value)

    def test_name_validation(self, value):
        if value+".csv" in os.listdir("./nic_time_reader"):
            return "Name already taken"
        if len(value) == 0:
            return "Name needs at least 1 character"
        return self.check_filename_validity(value)

    async def load_config_btn_handler(self):
        if not os.path.isdir("/home/usr/devel/ptp-test-platform/configs"):
            ui.notify("Could not find config directory", type="negative")
            return
        
        files = os.listdir("/home/usr/devel/ptp-test-platform/configs")

        self.config_file_table.rows = [{"name": file} for file in files]

        fname = await self.load_config_dialog.open()

        if fname is None:
            return
        
        with open(f"/home/usr/devel/ptp-test-platform/configs/{fname}") as f:
            config = json.load(f)

            self.config_table.config_table.rows = config

        self.compute_graph_handler()
        self.config_table.update()

    def developement_mode(self, value, elements):
        if value == "standard":
            for el in elements:
                el.set_visibility(False)
        elif value == "developement":
            for el in elements:
                el.set_visibility(True)
        else:
            ui.notify(f"Encountered unknown mode for the gui: {value}")

    def update_timer(self):
        if self.timer["locked"]:
            return
        self.timer["locked"] = True

        now = time.time()
        if self.timer["last_edit"] + 1 < now:
            if self.state["phase"] != self.timer["phase"]:
                self.timer["phase"] = self.state["phase"]
                
                if self.timer["phase"] == 1:
                    self.timer["text"] = "ptp4l initialization"
                    self.timer["time"] = self.times["ptp_init"]
                elif self.timer["phase"] == 2:
                    self.timer["text"] = "phc2sys warmup"
                    self.timer["time"] = self.times["phc_warm"]
                elif self.timer["phase"] == 3:
                    self.timer["text"] = "delay manipulation"
                    self.timer["time"] = self.timestamps[-1]
                else:
                    self.timer["text"] = "no test in progress"
                    self.timer["time"] = 0
            else:
                if self.timer["phase"] != 0:
                    self.timer["time"] =self.timer["time"]-(now-self.timer["last_edit"])

            self.timer["last_edit"] = now
            self.timer["time_str"] = f"{self.timer["time"]:.3f}s"
        
        self.timer["locked"] = False

    async def start_ptp_manip_btn_handler(self, filename):
        if filename is None or len(filename) == 0:
            ui.notify("Filename required to start test", type="negative")
            return
        
        self.waveform_generator.set_delay(0)

        msg = await self.test_handler.start_manipulation_test(filename, 
                                                  self.times["ptp_init"], 
                                                  self.times["phc_warm"], 
                                                  self.delay_handler,
                                                  self.waveform_generator)

        for client in Client.instances.values():
            with client:
                ui.notify(msg[0], type=msg[1])
    
    async def stop_manip_handler(self):
        self.test_handler.abort = True

    def build(self):
        @ui.page("/")
        def main_page():
            delay_graph = DelayGraph()
            self.config_table.register_event(lambda: self.update_graph(delay_graph))
            binding.bind(self.config_table.enabled, "enabled", self.test_handler.available, "enabled")

            with ui.header() as header:
                ui.space()
                ui.label("Page for configuring and starting ptp-(manipulation)-tests")
                ui.space()

            with ui.dialog() as self.save_config_dialog, ui.card():
                self.name_input = ui.input(label="Name", 
                                      validation=lambda value: self.config_name_validation(value))
                ui.button("submit", on_click=lambda:self.save_config_dialog.submit(self.name_input.value))
                self.save_config_dialog.on("escape-key", self.save_config_dialog.submit(None))

            with ui.dialog() as self.load_config_dialog, ui.card():
                ui.label("double-click an entry to select")
                self.config_file_table = ui.table(
                    columns=[{"name": "name", "label": "", "field": "name"}], 
                    rows=[]
                    ).on(
                        "row-dblclick", 
                        lambda e: self.load_config_dialog.submit(e.args[1]["name"])
                    ).props("hide-header").classes("w-full")
                self.load_config_dialog.on("escape-key", lambda: self.load_config_dialog.submit(None))

            with ui.column().classes("w-full"):
                with ui.row().classes('w-full') as fgen_row:
                    with ui.card(align_items="center").tight().props('flat'):
                        ui.label("Waveform Generator Address")
                        self.ip_address_input = ui.input(validation={
                            "Must be IP Address": lambda value: re.fullmatch(r"(\d+\.){3}\d+", value) is not None
                        }).props("dense")
                        self.ip_address_input.value = "10.100.2.193"
                        self.ip_address_input.update()
                    ui.button("Connect", on_click=self.connect_btn_handler)
                    self.connect_btn_handler()
                fgen_row.set_visibility(False)
                fgen_sep = ui.separator().classes("w-full").set_visibility(False)
                with ui.row().classes("w-full"):
                    with ui.column(), ui.card() as parent:
                        ui.label("Config Table")
                        with ui.row():
                            ui.button("Save Config", on_click=self.save_config_btn_handler).bind_enabled(self.test_handler.available)
                            ui.button("Load Config", on_click=self.load_config_btn_handler).bind_enabled(self.test_handler.available)
                        self.config_table.build(parent)
                    with ui.column(), ui.card():
                        with ui.row():
                            test_btn = ui.button("Start delay test", on_click=self.test_btn_handler)
                            test_btn.set_visibility(False)
                        with ui.row() as parent:
                            delay_graph.build(parent)
                            self.compute_graph_handler()
                            self.update_graph(delay_graph)
                    with ui.column() as test_col:
                            manip_btn = ui.button("Start manipulation test")
                            stop_btn = ui.button("Stop manipulation test")
                            with ui.card(), ui.column():
                                filename_input = ui.input(label="filename", validation=lambda value: self.test_name_validation(value)).bind_enabled(self.test_handler.available)
                                ui.number(label="ptp4l initialization time").bind_enabled(self.test_handler.available).bind_value(self.times, "ptp_init")
                                ui.number(label="phc2sys warmup time").bind_enabled(self.test_handler.available).bind_value(self.times, "phc_warm")
                            manip_btn.bind_enabled(self.test_handler.available)
                            manip_btn.on_click(lambda: background_tasks.create(self.start_ptp_manip_btn_handler(filename_input.value)))
                            stop_btn.bind_enabled(self.test_handler.unavailable)
                            stop_btn.on_click(self.stop_manip_handler)
                ui.separator().classes("w-full")
                with ui.row().classes("w-full"):
                    data_cols = {}
                    for dev in self.outfile_var_devices:
                        "#0066FF"
                        with ui.card().props("flat bordered"), ui.column().classes("gap-1"):
                            ui.label(dev).style("font-size: 150%;")
                            ui.separator()
                            data_cols[dev] = {}
                            with ui.row().style("gap: 0.3rem; background-color: #0066FF20;"):
                                with ui.column().classes("gap-1") as data_cols[dev]["main"]:
                                    ui.label("general").style("font-size: 125%;")
                                    ui.separator()
                                ui.separator().props("vertical")
                                with ui.column().classes("gap-1"):
                                    ui.label("ptp4l").style("font-size: 125%;")
                                    ui.separator()
                                    with ui.row().style("gap: 0.3rem;  background-color: #0066FF20;"):
                                        with ui.column().classes("gap-1") as data_cols[dev]["offset"]:
                                            ui.label("offset")
                                            ui.separator()
                                        ui.separator().props("vertical")
                                        with ui.column().classes("gap-1") as data_cols[dev]["freq"]:
                                            ui.label("freq")
                                            ui.separator()
                                        ui.separator().props("vertical")
                                        with ui.column().classes("gap-1") as data_cols[dev]["delay"]:
                                            ui.label("delay")
                                            ui.separator()                      

                    for var in self.state:
                        for dev in self.outfile_var_devices:
                            if var.find(dev)!=-1:
                                label = var
                                main_col = True
                                to_replace = f"ptp4l_{dev}_"

                                curr = data_cols[dev]
                                col = curr["main"]
                                if var.find("offset")!=-1:
                                    col = curr["offset"]
                                    to_replace = to_replace+"offset_"
                                    main_col = False
                                elif var.find("freq")!=-1:
                                    col = curr["freq"]
                                    to_replace = to_replace+"freq_"
                                    main_col = False
                                elif var.find("delay")!=-1:
                                    col = curr["delay"]
                                    to_replace = to_replace+"delay_"
                                    main_col = False

                                if not main_col:
                                    label = label.replace(to_replace, "")

                                with col:
                                    ui.label(label)
                                    ui.label().bind_text_from(self.state_str, var)
                                    ui.separator()

                    with test_col, ui.card():
                        ui.label().bind_text(self.timer, "text")
                        ui.label().bind_text(self.timer, "time_str")

                        ui.timer(0.1, lambda: self.update_timer())

            with header:
                with ui.button(icon="settings").props("unelevated"):
                        with ui.menu().style("background-color: #00000000;"):
                            with ui.card().tight().props("flat"):
                                off_btn = ui.button(icon="power_settings_new", on_click=app.shutdown).props("unelevated").classes("w-full")
                                off_btn.set_visibility(False)
                                test_toggle = ui.toggle({True: "Test enabled", False: "Test disabled"}
                                                        ).bind_value(self.test_handler.available, "enabled").classes("w-full")
                                test_toggle.set_visibility(False)
                                ui.toggle(["standard", "developement"], value="standard", on_change=lambda e: self.developement_mode(e.value, [test_btn, off_btn, test_toggle, fgen_row, fgen_sep])).classes("w-full")

            ui.timer(1, self.update_outputs)