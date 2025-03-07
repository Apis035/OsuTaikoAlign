#+build windows
package main

import "core:os"
import "core:mem"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:math/rand"
import "core:sys/windows"

DEBUG :: #config(debug, false)

main :: proc() {
	exitCode: int
	defer os.exit(exitCode)

	when DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)

		context.allocator = mem.tracking_allocator(&track)

		defer {
			for _, leak in track.allocation_map {
				fmt.printf("%v leaked %m\n", leak.location, leak.size)
			}
			for bad_free in track.bad_free_array {
				fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
			}
		}
	}

	windows.SetConsoleOutputCP(.UTF8)

	exitCode = Main()
}

Main :: proc() -> int {
	/*
		get clipboard data
		parse beatmap
		check if data is a osu beatmap
		ask note align style
		align note
		set clipboard data
		done
	*/

	LogStatus("* Getting clipboard content")

	//NOTE: data is using temp_allocator, no need to delete()
	data, getOk := GetClipboard()
	if !getOk {
		fmt.eprintln("Fail to get clipboard content. Clipboard is empty or does not contain text data.")
		return 1
	}

	LogStatus("* Parsing beatmap")

	beatmap, parseErr := ParseBeatmap(data)
	when DEBUG {
		fmt.println("---- Beatmap data ----")
		PrintBeatmap(beatmap)
		fmt.println("---- Beatmap data ----")
	}
	if parseErr != nil {
		fmt.eprintln("Fail to parse beatmap:", parseErr)
		return 1
	}

	fmt.println("How do you want to align the notes?")
	fmt.println("   1. All center")
	fmt.println("   2. Normal center, finisher above")
	fmt.println("   3. Don left, kat right")
	fmt.println("   4. Don left, kat right, finisher above")
	fmt.println("   5. Don left, kat right, finisher above center")
	fmt.println("   6. Scatter all")
	fmt.print  ("   > ")
	choice := Choice("123456")
	if choice == CHOICE_CTRL_C {
		fmt.println("Terminating")
		return 0
	}

	LogStatus("* Aligning beatmap notes")

	alignStyle := AlignStyle(choice - '1')
	AlignObjects(&beatmap, alignStyle)

	LogStatus("* Copying processed beatmap into clipboard")

	beatmapText := UnparseBeatmap(beatmap)
	defer delete(beatmapText)

	setOk := SetClipboard(beatmapText)
	if !setOk {
		fmt.eprintln("Fail to set clipboard content.")
		return 1
	}

	fmt.println()
	fmt.println("--- Paste back the processed data into your beatmap. ---")
	return 0
}

@(disabled = DEBUG == false)
LogStatus :: proc(s: string) {
	fmt.println(s)
}

/*****************************************************************************/

Beatmap :: struct {
	unusedData : string,
	objects    : Objects,
}

Vec2 :: [2]int

Objects :: [dynamic]Object

Object :: struct {
	pos      : Vec2,
	time     : int,
	type     : int,
	hitsound : int,
	extra    : string,
}

ParseError :: union #shared_nil {
	BeatmapParseError,
	HitObjectParseError,
	mem.Allocator_Error,
}

BeatmapParseError :: enum {
	None,
	Empty_Data,
	Invalid_Beatmap_Data,
}

HitObjectParseError :: enum {
	None,
	Invalid_HitObject_Data,
}

//TODO: translate error enum to message
//ParseErrorMessage :: proc(err: ParseError) -> string

ParseBeatmap :: proc(data: string) -> (beatmap: Beatmap, err: ParseError) {
	osuFormatHeader :: "osu file format v14"
	hoSectionName   :: "[HitObjects]"
	hoSectionOffset := strings.index(data, hoSectionName)

	if len(data) == 0 {
		return {}, .Empty_Data
	}
	if hoSectionOffset == -1 || data[:len(osuFormatHeader)] != osuFormatHeader {
	   	return {}, .Invalid_Beatmap_Data
	}

	// Move offset after the section line + newline
	hoSectionOffset += len(hoSectionName) + 1

	beatmap.unusedData = data[:hoSectionOffset]
	beatmap.objects = ParseObjects(data[hoSectionOffset:]) or_return

	return beatmap, nil
}

UnparseBeatmap :: proc(beatmap: Beatmap) -> string {
	sb: strings.Builder
	fmt.sbprintf(&sb, "%s", beatmap.unusedData)
	for o in beatmap.objects {
		fmt.sbprintfln(&sb, "%d,%d,%d,%d,%d,%s", o.pos.x, o.pos.y, o.time, o.type, o.hitsound, o.extra)
	}
	return strings.to_string(sb)
}

ParseObjects :: proc(data: string) -> (hitObjects: Objects, err: ParseError) {
	ParseIntOrErr :: proc(s: string) -> (value: int, err: ParseError) {
		v, ok := strconv.parse_int(s)
		if !ok do return v, .Invalid_HitObject_Data
		return v, nil
	}

	data := data
	for line in strings.split_lines_iterator(&data) {
		(line != "") or_continue

		tokens := strings.split_n(line, ",", 6) or_return
		if len(tokens) < 5 do return hitObjects, .Invalid_HitObject_Data

		o: Object
		o.pos.x    = ParseIntOrErr(tokens[0]) or_return
		o.pos.y    = ParseIntOrErr(tokens[1]) or_return
		o.time     = ParseIntOrErr(tokens[2]) or_return
		o.type     = ParseIntOrErr(tokens[3]) or_return
		o.hitsound = ParseIntOrErr(tokens[4]) or_return
		o.extra    = tokens[5]

		append(&hitObjects, o)
	}

	return hitObjects, nil
}

PrintBeatmap :: proc(beatmap: Beatmap) {
	str := UnparseBeatmap(beatmap)
	defer delete(str)
	fmt.println(str)
}

/*****************************************************************************/

AlignStyle :: enum {
	AllCenter,
	NormalCenterFinisherTop,
	DonLeftKatRight,
	DonLeftKatRightFinisherTop,
	DonLeftKatRightFinisherCenterTop,
	Scatter,
}

ObjectType :: enum {
	Don,
	Kat,
	DonFinish,
	KatFinish,
	Slider,
	Spinner,
}

POS_LEFT       :: Vec2{192, 192}
POS_CENTER     :: Vec2{256, 192}
POS_RIGHT      :: Vec2{320, 192}
POS_TOP_LEFT   :: Vec2{192, 96}
POS_TOP_CENTER :: Vec2{256, 96}
POS_TOP_RIGHT  :: Vec2{320, 96}

@(rodata)
AlignTable := [AlignStyle][ObjectType]Vec2 {
	.AllCenter = #partial {
		.Don       = POS_CENTER,
		.Kat       = POS_CENTER,
		.DonFinish = POS_CENTER,
		.KatFinish = POS_CENTER,
	},
	.NormalCenterFinisherTop = #partial {
		.Don       = POS_CENTER,
		.Kat       = POS_CENTER,
		.DonFinish = POS_TOP_CENTER,
		.KatFinish = POS_TOP_CENTER,
	},
	.DonLeftKatRight = #partial {
		.Don       = POS_LEFT,
		.Kat       = POS_RIGHT,
		.DonFinish = POS_LEFT,
		.KatFinish = POS_RIGHT,
	},
	.DonLeftKatRightFinisherTop = #partial {
		.Don       = POS_LEFT,
		.Kat       = POS_RIGHT,
		.DonFinish = POS_TOP_LEFT,
		.KatFinish = POS_TOP_RIGHT,
	},
	.DonLeftKatRightFinisherCenterTop = #partial {
		.Don       = POS_LEFT,
		.Kat       = POS_RIGHT,
		.DonFinish = POS_TOP_CENTER,
		.KatFinish = POS_TOP_CENTER,
	},
	.Scatter = {} // Manual
}

AlignObjects :: proc(beatmap: ^Beatmap, style: AlignStyle) {
	for &o in beatmap.objects {
		noteType := GetObjectType(o)

		if noteType == .Slider || noteType == .Spinner {
			continue
		}

		if style == .Scatter {
			x := rand.int_max(512)
			y := rand.int_max(384)
			o.pos = {x, y}
		} else {
			o.pos = AlignTable[style][noteType]
		}
	}
}

GetObjectType :: proc(o: Object) -> ObjectType {
	switch o.extra[0] {
		case 'B', 'L':  return .Slider
	}
	switch o.hitsound {
		case 0:         return .Don
		case 4:         return .DonFinish
		case 2, 8, 10:  return .Kat
		case 6, 12, 14: return .KatFinish
	}
	switch o.extra[0] {
		case '0'..='9': return .Spinner
	}
	fmt.panicf("unknown object type: %d,%d,%d,%d,%d,%s", o.pos.x, o.pos.y, o.time, o.type, o.hitsound, o.extra)
}

/*****************************************************************************/

GetClipboard :: proc() -> (data: string, ok: bool) {
	using windows

	OpenClipboard(nil) or_return
	defer CloseClipboard()

	clipboard := HGLOBAL(GetClipboardData(CF_UNICODETEXT))
	(clipboard != nil) or_return

	pText := cast(wstring)GlobalLock(clipboard)
	(pText != nil) or_return
	defer GlobalUnlock(clipboard)

	text, _ := wstring_to_utf8(pText, -1)
	return text, true
}

SetClipboard :: proc(data: string) -> (ok: bool) {
	using windows

	wData := utf8_to_utf16(data)
	length := len(wData)*2+2

	OpenClipboard(nil) or_return
	defer CloseClipboard()

	hMem := GlobalAlloc(GMEM_MOVEABLE, uint(length))
	(hMem != nil) or_return

	dest := GlobalLock(HGLOBAL(hMem))
	(dest != nil) or_return
	defer GlobalUnlock(HGLOBAL(hMem))

	s := slice.from_ptr(cast(wstring)dest, length)
	copy(s, wData[:])

	SetClipboardData(CF_UNICODETEXT, HANDLE(hMem))

	return true
}

CHOICE_CTRL_C :: 3

Choice :: proc(choices: string) -> rune {
    for {
        char := getch()
        for choice in choices do if char == choice {
        	fmt.println(char)
            return char
        }
        if char == CHOICE_CTRL_C {
        	return char
        }
    }
}

/*****************************************************************************/

getch :: proc() -> (r: rune) {
	using windows
	mode, n: DWORD
	h := GetStdHandle(STD_INPUT_HANDLE)
	GetConsoleMode(h, &mode)
	SetConsoleMode(h, mode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT))
	ReadConsoleW(h, &r, 1, &n, nil)
	SetConsoleMode(h, mode)
	return
}

@(deprecated="unhelpful error message")
GetWindowsErrorMsg :: proc() -> string {
	using windows

	buf: [64]WCHAR
	pBuf := cast(wstring)&buf
	length := FormatMessageW(
		FORMAT_MESSAGE_FROM_SYSTEM, nil, GetLastError(),
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), pBuf, len(buf), nil)

	msg, _ := wstring_to_utf8(pBuf, int(length))
	return msg
}