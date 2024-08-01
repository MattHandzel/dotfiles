echo "RESETTING HID_MULTITOUCH"

rmmod hid_multitouch
modprobe hid_multitouch 

xinput set-prop 12 307 1  
