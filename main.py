from nicegui import ui, app
from gui import MainPage
from handlers import TestHandler, DelayHandler
from scpi import KEYSIGHT_33600A
import pyvisa

rm = None
fgen = None
test_handler = None
delay_handler = None
main_page = None

def startup():
    global rm, fgen, test_handler, delay_handler, main_page

    rm = pyvisa. ResourceManager()
    fgen = KEYSIGHT_33600A(rm, "10.100.2.193")

    test_handler = TestHandler()
    delay_handler = DelayHandler()

    main_page = MainPage(delay_handler, fgen, test_handler)
    main_page.build()

async def shutdown_handler():
    if fgen is not None:
        fgen.close()
    if test_handler is not None:
        await test_handler.stop_test()

app.on_startup(startup)
app.on_shutdown(shutdown_handler)

try:
    ui.run(reload=False)
except Exception as e:
    print("An exception occured:")
    print(e)

    shutdown_handler()