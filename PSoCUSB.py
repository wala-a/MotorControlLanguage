import usb.core
import usb.util
import usb.core
import array

# search for our device by product and vendor ID
dev = usb.core.find(idVendor=0x4b4, idProduct=0x80)

# raise error if device is not found
if dev is None:
	raise ValueError('device not found')
	
# set the active configuragtion (basically, start the device)
dev.set_configuration()

# get interface 0, alternate setting 0
intf = dev.get_active_configuration()[(0,0)]

# find the first (and in this case only) OUT endpoint in our interface
epOut = usb.util.find_descriptor(
					intf,
					custom_match = \
					lambda e:	\
							usb.util.endpoint_direction(e.bEndpointAddress) == \
							usb.util.ENDPOINT_OUT)
							
# find the first and in this case only IN endpoint in our interface
epIn = usb.util.find_descriptor(
					intf,
					custom_match = \
					lambda e:	\
							usb.util.endpoint_direction(e.bEndpointAddress) == \
							usb.util.ENDPOINT_IN)

# make sure our endpoints were found
assert epOut is not None
assert epIn is not None

while (True):
	t = input()	+ "\r\n"									  #get the user input
	i = len(t)
	epOut.write(t) 
	print(''.join([chr(l) for l in epIn.read(100)])) #receive the echo

	try:
		print("trying to receive more data")
		print(''.join([chr(l) for l in epIn.read(100, timeout=10000)])) #receive the echo
	except usb.core.USBError as e:
		print("failed to receive more data")
		pass
