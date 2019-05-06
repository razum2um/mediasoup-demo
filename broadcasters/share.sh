# https://gist.githubusercontent.com/tomasinouk/8415acb4e2f86d54fcb9/raw/83225dbb382ac9e57671d12efe4c2c3efa236260/ffmpeg_examples.md

# `ffmpeg -f avfoundation -i "1" -vcodec libx264 -r 10 -tune zerolatency -b:v 500k -bufsize 300k -f rtp rtp://localhost:1234`

# `ffmpeg -f avfoundation -i "1" -vcodec libx264 -r 10 -tune zerolatency -b:v 500k -bufsize 300k -f rtp udp://127.0.0.1:1234`


# `ffmpeg -f avfoundation -i "1" -vcodec libx264 -r 10 -tune zerolatency -b:v 500k -bufsize 300k -f mpegts udp://127.0.0.1:1234`


# `ffmpeg -f avfoundation -i "1" -vcodec libx264 -r 10 -pix_fmt uyvy422 -tune zerolatency -b:v 500k -bufsize 300k -f mpegts udp://192.168.88.38:1234`


# ffmpeg -f avfoundation -i "1" -r 50 -vcodec mpeg2video -b:v 8000 -f mpegts udp://192.168.88.38:1234

# ffmpeg -f x11grab -s 1600x900 -r 50 -vcodec libx264 -preset ultrafast -tune zerolatency -crf 18 -f mpegts udp://localhost:1234

# ## Mac OSX

# -pix_fmt format set pixel format
# -crf E..V…. Select the quality for constant quality mode (from 0 to 63) (default 0)
# [avfoundation @ 0x7fb3f1801000] Selected pixel format (yuv420p) is not supported by the input device.
# [avfoundation @ 0x7fb3f1801000] Supported pixel formats:
# [avfoundation @ 0x7fb3f1801000]   uyvy422
# [avfoundation @ 0x7fb3f1801000]   yuyv422
# [avfoundation @ 0x7fb3f1801000]   nv12
# [avfoundation @ 0x7fb3f1801000]   0rgb
# [avfoundation @ 0x7fb3f1801000]   bgr0

# `ffmpeg -f avfoundation -i "1" -r 10 -vcodec libx264 -preset ultrafast  -tune zerolatency -crf 18 -b:v 500k -bufsize 300k -f mpegts udp://192.168.88.38:1234`

# `ffmpeg -f avfoundation -i "1" -r 10 -vcodec libx264 -pix_fmt uyvy422   -tune zerolatency         -b:v 500k -bufsize 300k -f mpegts udp://192.168.88.38:1234`

# ## Windows

# `ffmpeg -f dshow -i video="screen-capture-recorder" -r 10 -vcodec libx264 -preset ultrafast -tune zerolatency -crf 18 -b:v 500k -bufsize 300k -f mpegts udp://172.31.66.20:1234`


# -crf 18

# -pix_fmt yuv420p
# -f mpegts

#!/usr/bin/env bash

function show_usage()
{
	echo
	echo "USAGE"
	echo "-----"
	echo
	echo "  SERVER_URL=https://my.mediasoup-demo.org:4443 ROOM_ID=test MEDIA_FILE=./test.mp4 ./ffmpeg.sh"
	echo
	echo "  where:"
	echo "  - SERVER_URL is the URL of the mediasoup-demo API server"
	echo "  - ROOM_ID is the id of the mediasoup-demo room (it must exist in advance)"
	echo "  - MEDIA_FILE is the path to a audio+video file (such as a .mp4 file)"
	echo
	echo "REQUIREMENTS"
	echo "------------"
	echo
	echo "  - ffmpeg: stream audio and video (https://www.ffmpeg.org)"
	echo "  - httpie: command line HTTP client (https://httpie.org)"
	echo "  - jq: command-line JSON processor (https://stedolan.github.io/jq)"
	echo
}

echo

if [ -z "${SERVER_URL}" ] ; then
	>&2 echo "ERROR: missing SERVER_URL environment variable"
	show_usage
	exit 1
fi

if [ -z "${ROOM_ID}" ] ; then
	>&2 echo "ERROR: missing ROOM_ID environment variable"
	show_usage
	exit 1
fi

if [ -z "${MEDIA_FILE}" ] ; then
	>&2 echo "ERROR: missing MEDIA_FILE environment variable"
	show_usage
	exit 1
fi

if [ "$(command -v ffmpeg)" == "" ] ; then
	>&2 echo "ERROR: ffmpeg command not found, must install FFmpeg"
	show_usage
	exit 1
fi

if [ "$(command -v http)" == "" ] ; then
	>&2 echo "ERROR: http command not found, must install httpie"
	show_usage
	exit 1
fi

if [ "$(command -v jq)" == "" ] ; then
	>&2 echo "ERROR: jq command not found, must install jq"
	show_usage
	exit 1
fi

set -e

BROADCASTER_ID=$(LC_CTYPE=C tr -dc A-Za-z0-9 < /dev/urandom | fold -w ${1:-32} | head -n 1)
HTTPIE_COMMAND="http --check-status --verify=no"
AUDIO_SSRC=1111
AUDIO_PT=100
VIDEO_SSRC=2222
VIDEO_PT=101

#
# Verify that a room with id ROOM_ID does exist by sending a simlpe HTTP GET. If
# not abort since we are not allowed to initiate a room..
#
echo ">>> verifying that room '${ROOM_ID}' exists..."

${HTTPIE_COMMAND} \
	GET ${SERVER_URL}/rooms/${ROOM_ID} > /dev/null

#
# Create a Broadcaster entity in the server by sending a POST with our metadata.
# Note that this is not related to mediasoup at all, but will become just a JS
# object in the Node.js application to hold our metadata and mediasoup Transports
# and Producers.
#
echo ">>> creating Broadcaster..."

${HTTPIE_COMMAND} \
	POST ${SERVER_URL}/rooms/${ROOM_ID}/broadcasters \
	id="${BROADCASTER_ID}" \
	displayName="Broadcaster Share" \
	device:='{"name": "FFmpeg Share"}' \
	> /dev/null

#
# Upon script termination delete the Broadcaster in the server by sending a
# HTTP DELETE.
#
trap 'echo ">>> script exited with status code $?"; ${HTTPIE_COMMAND} DELETE ${SERVER_URL}/rooms/${ROOM_ID}/broadcasters/${BROADCASTER_ID} > /dev/null' EXIT

#
# Create a PlainRtpTransport in the mediasoup to send our audio and video tracks
# using plain RTP over UDP. Do it via HTTP post specifying type:"plain" and
# multiSource:true to tell the server to accept RTP from any IP:port (we can do
# this because we know that ffmpeg does not expect to receive RTCP).
#
echo ">>> creating mediasoup PlainRtpTransport for producing audio and video..."

res=$(${HTTPIE_COMMAND} \
	POST ${SERVER_URL}/rooms/${ROOM_ID}/broadcasters/${BROADCASTER_ID}/transports \
	type="plain" \
	multiSource:=true \
	2> /dev/null)

#
# Parse JSON response into Shell variables and extract the PlainRtpTransport id,
# IP and port.
#
eval "$(echo ${res} | jq -r '@sh "transportId=\(.id) transportIp=\(.ip) transportPort=\(.port)"')"

#
# Create a mediasoup Producer to send audio by sending our RTP parameters via a
# HTTP POST.
#
echo ">>> creating mediasoup audio Producer..."

${HTTPIE_COMMAND} -v \
	POST ${SERVER_URL}/rooms/${ROOM_ID}/broadcasters/${BROADCASTER_ID}/transports/${transportId}/producers \
	kind="audio" \
	rtpParameters:="{ \"codecs\": [{ \"mimeType\":\"audio/opus\", \"payloadType\":${AUDIO_PT}, \"clockRate\":48000, \"channels\":2, \"parameters\":{ \"sprop-stereo\":1 } }], \"encodings\": [{ \"ssrc\":${AUDIO_SSRC} }] }" \
	> /dev/null

#
# Create a mediasoup Producer to send video by sending our RTP parameters via a
# HTTP POST.
#
echo ">>> creating mediasoup video Producer..."

${HTTPIE_COMMAND} -v \
	POST ${SERVER_URL}/rooms/${ROOM_ID}/broadcasters/${BROADCASTER_ID}/transports/${transportId}/producers \
	kind="video" \
	rtpParameters:="{ \"codecs\": [{ \"mimeType\":\"video/vp8\", \"payloadType\":${VIDEO_PT}, \"clockRate\":90000 }], \"encodings\": [{ \"ssrc\":${VIDEO_SSRC} }] }" \
	> /dev/null

#
# Run ffmpeg command and make it send audio and video RTP with codec payload and
# SSRC values matching those that we have previously signaled in the Producers
# creation above. Also, tell ffmpeg to send the RTP to the mediasoup
# PlainRtpTransport ip and port.
#
echo ">>> running ffmpeg..."

# ffmpeg -f avfoundation -i "1" -r 10 -vcodec libx264 -preset ultrafast  -tune zerolatency -crf 18 -b:v 500k -bufsize 300k -f mpegts udp://192.168.88.38:1234
# -pix_fmt yuv420p -c:v libvpx -b:v 1000k -bufsize 300k -cpu-used 4 \

ffmpeg \
	-v info \
	-f avfoundation -i "1" \
	-vf "scale=-1:480" \
	-map 0:v:0 \
	-pix_fmt yuv420p -c:v libvpx -b:v 1000k -deadline realtime -cpu-used 4 -vsync 2 \
	-f tee \
	"[select=v:f=rtp:ssrc=${VIDEO_SSRC}:payload_type=${VIDEO_PT}]rtp://${transportIp}:${transportPort}"

# run but not works
# ffmpeg \
# 	-v info \
# 	-f avfoundation -i "1" \
# 	-map 0:v:0 \
# 	-r 10 -vcodec libx264 -preset ultrafast  -tune zerolatency -crf 18 -b:v 500k \
# 	-f mpegts "udp://${transportIp}:${transportPort}"

	#-f tee \
	#"[select=v:f=rtp:ssrc=${VIDEO_SSRC}:payload_type=${VIDEO_PT}]rtp://${transportIp}:${transportPort}"

