package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"reflect"

	"generated_contracts/common"
	"generated_contracts/orders"
	"generated_contracts/wire"
)

type entry struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Wire     string `json:"wire"`
	Semantic bool   `json:"semantic,omitempty"`
}

type roundtrip func(string) (string, error)

func structText[T any](from func(string) (T, error), to func(T) (string, error)) roundtrip {
	return func(text string) (string, error) {
		value, err := from(text)
		if err != nil {
			return "", err
		}
		return to(value)
	}
}

var registry = map[string]roundtrip{
	"Orders.ReserveRequest": structText(orders.ReserveRequestFromDrut, orders.ReserveRequestToDrut),
	"Orders.Reservation":    structText(orders.ReservationFromDrut, orders.ReservationToDrut),
	"Orders.Problem":        structText(orders.ProblemFromDrut, orders.ProblemToDrut),
	"Orders.ReserveResponse": structText(orders.ReserveResponseFromDrut,
		orders.ReserveResponseToDrut),
	"Orders.ReservationBatch": structText(orders.ReservationBatchFromDrut,
		orders.ReservationBatchToDrut),
	"Orders.Guard":       structText(orders.GuardFromDrut, orders.GuardToDrut),
	"Orders.ListBox":     structText(orders.ListBoxFromDrut, orders.ListBoxToDrut),
	"Orders.ResponseBox": structText(orders.ResponseBoxFromDrut, orders.ResponseBoxToDrut),
	"Orders.Scalars":     structText(orders.ScalarsFromDrut, orders.ScalarsToDrut),
	"Common.UserCtx":     structText(common.UserCtxFromDrut, common.UserCtxToDrut),
	"Common.Wrapper":     structText(common.WrapperFromDrut, common.WrapperToDrut),
	"Common.Blob":        structText(common.BlobFromDrut, common.BlobToDrut),
	"Common.Empty":       structText(common.EmptyFromDrut, common.EmptyToDrut),
	"Common.VoidBox":     structText(common.VoidBoxFromDrut, common.VoidBoxToDrut),
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, "FAIL:", message)
	os.Exit(1)
}

func readEntries(path string) []entry {
	data, err := os.ReadFile(path)
	if err != nil {
		fail(err.Error())
	}
	var entries []entry
	if err := json.Unmarshal(data, &entries); err != nil {
		fail(err.Error())
	}
	return entries
}

func roundtripEntry(item entry) (string, error) {
	ops, ok := registry[item.Type]
	if !ok {
		return "", fmt.Errorf("unknown type %s", item.Type)
	}
	return ops(item.Wire)
}

func sameJSON(left, right string) bool {
	var a, b any
	if err := json.Unmarshal([]byte(left), &a); err != nil {
		return false
	}
	if err := json.Unmarshal([]byte(right), &b); err != nil {
		return false
	}
	return reflect.DeepEqual(a, b)
}

func check(argv []string) {
	entries := readEntries(argv[0])
	results := make([]entry, 0, len(entries))
	for _, item := range entries {
		reencoded, err := roundtripEntry(item)
		if err != nil {
			fail(item.ID + " (" + item.Type + "): " + err.Error())
		}
		matches := reencoded == item.Wire
		if item.Semantic {
			matches = sameJSON(reencoded, item.Wire)
		}
		if !matches {
			fail(item.ID + " (" + item.Type + "): " + reencoded + " != " + item.Wire)
		}
		results = append(results, entry{ID: item.ID, Type: item.Type, Wire: reencoded, Semantic: item.Semantic})
	}
	output, err := json.MarshalIndent(results, "", "  ")
	if err != nil {
		fail(err.Error())
	}
	if err := os.WriteFile(argv[1], output, 0o644); err != nil {
		fail(err.Error())
	}
	fmt.Printf("go verified %d fixture(s)\n", len(entries))
}

func verify(argv []string) {
	entries := readEntries(argv[0])
	for _, item := range entries {
		reencoded, err := roundtripEntry(item)
		if err != nil {
			fail(item.ID + " (" + item.Type + "): " + err.Error())
		}
		if !sameJSON(reencoded, item.Wire) {
			fail(item.ID + " (" + item.Type + "): " + reencoded + " != " + item.Wire)
		}
	}
	fmt.Printf("go decoded %d message(s) from peer\n", len(entries))
}

func invalid(argv []string) {
	entries := readEntries(argv[0])
	for _, item := range entries {
		if _, err := roundtripEntry(item); err == nil {
			fail(item.ID + " (" + item.Type + "): invalid wire accepted")
		}
	}
	var response orders.ReserveResponse = orders.ReserveResponseUnavailable{}
	if _, err := orders.ReserveResponseToDrut(response); err != nil {
		fail("valid variant rejected: " + err.Error())
	}
	if _, err := orders.ReserveResponseToDrut(nil); err == nil {
		fail("nil variant accepted")
	}
	if _, err := orders.ReserveResponseFromDrut("[\"Nope\",null]"); err == nil {
		fail("unknown tag accepted")
	}
	fmt.Printf("go rejected %d invalid message(s)\n", len(entries))
}

type drutCase struct {
	ID          string          `json:"id"`
	Type        json.RawMessage `json:"type"`
	Category    string          `json:"category"`
	Utf8Invalid bool            `json:"utf8_invalid"`
	Wire        *string         `json:"wire"`
	WireHex     *string         `json:"wire_hex"`
	Value       json.RawMessage `json:"value"`
}

func (item drutCase) status(valid bool) string {
	if valid {
		if item.Category == "public" {
			return "executed"
		}
		return "executed-runtime"
	}
	if item.Category == "public" {
		return "rejected"
	}
	return "rejected-runtime"
}

type drutResult struct {
	ID     string `json:"id"`
	Status string `json:"status"`
}

func readDrut(path string) []drutCase {
	data, err := os.ReadFile(path)
	if err != nil {
		fail(err.Error())
	}
	var cases []drutCase
	if err := json.Unmarshal(data, &cases); err != nil {
		fail(err.Error())
	}
	return cases
}

func (item drutCase) isNamed() bool {
	var desc any
	if err := json.Unmarshal(item.Type, &desc); err != nil {
		return false
	}
	name, ok := desc.(string)
	if !ok {
		return false
	}
	switch name {
	case "void", "int", "float", "bool", "string", "date", "record":
		return false
	}
	return true
}

func (item drutCase) bytes() string {
	if item.WireHex != nil {
		decoded, err := hex.DecodeString(*item.WireHex)
		if err != nil {
			fail(item.ID + ": " + err.Error())
		}
		return string(decoded)
	}
	if item.Wire != nil {
		return *item.Wire
	}
	fail(item.ID + ": case has neither wire nor wire_hex")
	return ""
}

func decodeDesc(desc any, value any) (any, error) {
	switch typed := desc.(type) {
	case string:
		switch typed {
		case "void":
			if err := wire.AsNull(value, ""); err != nil {
				return nil, err
			}
			return nil, nil
		case "int":
			return wire.AsInt(value, "")
		case "float":
			return wire.AsFloat(value, "")
		case "bool":
			return wire.AsBool(value, "")
		case "string", "date":
			return wire.AsString(value, "")
		case "record":
			return wire.AsRecord(value, "")
		default:
			return nil, fmt.Errorf("unknown type %s", typed)
		}
	case map[string]any:
		inner, ok := typed["list"]
		if !ok {
			return nil, fmt.Errorf("unsupported root descriptor")
		}
		arr, err := wire.AsArray(value, "", -1)
		if err != nil {
			return nil, err
		}
		out := make([]any, len(arr))
		for index, item := range arr {
			decoded, err := decodeDesc(inner, item)
			if err != nil {
				return nil, err
			}
			out[index] = decoded
		}
		return out, nil
	default:
		return nil, fmt.Errorf("unsupported root descriptor")
	}
}

func drutJson(text string) any {
	var value any
	if err := json.Unmarshal([]byte(text), &value); err != nil {
		fail(err.Error())
	}
	return value
}

func runDrutCase(item drutCase) (any, error) {
	text := item.bytes()
	var desc any
	if err := json.Unmarshal(item.Type, &desc); err != nil {
		return nil, err
	}
	if name, ok := desc.(string); ok {
		if _, primitive := map[string]bool{
			"void": true, "int": true, "float": true, "bool": true,
			"string": true, "date": true, "record": true,
		}[name]; !primitive {
			ops, found := registry[name]
			if !found {
				return nil, fmt.Errorf("unknown type %s", name)
			}
			reencoded, err := ops(text)
			if err != nil {
				return nil, err
			}
			return drutJson(reencoded), nil
		}
	}
	value, err := wire.ParseText(text)
	if err != nil {
		return nil, err
	}
	produced, err := decodeDesc(desc, value)
	if err != nil {
		return nil, err
	}
	text2, err := wire.Stringify(produced)
	if err != nil {
		return nil, err
	}
	return drutJson(text2), nil
}

func drut(validPath, invalidPath, resultPath string) {
	valid := readDrut(validPath)
	invalid := readDrut(invalidPath)
	results := make([]drutResult, 0, len(valid)+len(invalid))
	for _, item := range valid {
		produced, err := runDrutCase(item)
		if err != nil {
			fail(item.ID + ": " + err.Error())
		}
		var expected any
		if item.isNamed() {
			if item.Wire == nil {
				fail(item.ID + ": named case without wire")
			}
			expected = drutJson(*item.Wire)
		} else {
			expected = drutJson(string(item.Value))
		}
		if !reflect.DeepEqual(produced, expected) {
			fail(item.ID + ": produced value does not match")
		}
		results = append(results, drutResult{ID: item.ID, Status: item.status(true)})
	}
	for _, item := range invalid {
		if _, err := runDrutCase(item); err == nil {
			fail(item.ID + ": invalid wire accepted")
		}
		results = append(results, drutResult{ID: item.ID, Status: item.status(false)})
	}
	output, err := json.MarshalIndent(results, "", "  ")
	if err != nil {
		fail(err.Error())
	}
	if err := os.WriteFile(resultPath, output, 0o644); err != nil {
		fail(err.Error())
	}
	fmt.Printf("go drut: %d executed, %d rejected\n", len(valid), len(invalid))
}

// optional checks the distinction between an absent optional field and a
// present empty string, empty slice or variant, including nil pointer versus
// pointer to a nil/empty slice.
func optional() {
	fail := func(message string) {
		fmt.Fprintln(os.Stderr, "FAIL: "+message)
		os.Exit(1)
	}
	expect := func(label, got, want string) {
		if got != want {
			fail(label + ": " + got + " != " + want)
		}
	}

	absent, err := orders.ReserveRequestToDrut(orders.ReserveRequest{OwnerID: "o1", Quantity: 2})
	if err != nil {
		fail(err.Error())
	}
	expect("absent string", absent, `["o1",2,null]`)
	empty := ""
	present, err := orders.ReserveRequestToDrut(orders.ReserveRequest{OwnerID: "o1", Quantity: 2, Note: &empty})
	if err != nil {
		fail(err.Error())
	}
	expect("present empty string", present, `["o1",2,""]`)
	if absent == present {
		fail("absent and empty string encode identically")
	}
	decoded, err := orders.ReserveRequestFromDrut(absent)
	if err != nil {
		fail(err.Error())
	}
	if decoded.Note != nil {
		fail("decoded absent string is not nil")
	}
	decoded, err = orders.ReserveRequestFromDrut(present)
	if err != nil {
		fail(err.Error())
	}
	if decoded.Note == nil || *decoded.Note != "" {
		fail("decoded empty string is not a present empty value")
	}

	nilList, err := orders.ListBoxToDrut(orders.ListBox{Items: nil})
	if err != nil {
		fail(err.Error())
	}
	expect("absent list", nilList, "[null]")
	emptySlice := []orders.Reservation{}
	emptyList, err := orders.ListBoxToDrut(orders.ListBox{Items: &emptySlice})
	if err != nil {
		fail(err.Error())
	}
	expect("empty list", emptyList, "[[]]")
	if nilList == emptyList {
		fail("nil pointer and empty slice encode identically")
	}
	decodedList, err := orders.ListBoxFromDrut(emptyList)
	if err != nil {
		fail(err.Error())
	}
	if decodedList.Items == nil || len(*decodedList.Items) != 0 {
		fail("decoded empty list is not a present empty slice")
	}

	nilVariant, err := orders.ResponseBoxToDrut(orders.ResponseBox{Response: nil})
	if err != nil {
		fail(err.Error())
	}
	expect("absent variant", nilVariant, "[null]")
	var unavailable orders.ReserveResponse = orders.ReserveResponseUnavailable{}
	presentVariant, err := orders.ResponseBoxToDrut(orders.ResponseBox{Response: &unavailable})
	if err != nil {
		fail(err.Error())
	}
	expect("present void variant", presentVariant, `[["Unavailable",null]]`)

	if _, err := orders.ReserveRequestFromDrut(`["o1","x",null]`); err == nil {
		fail("wrong required type accepted")
	}
	fmt.Println("go optional checks passed")
}

func main() {
	if len(os.Args) < 2 {
		fail("usage: interop <check|verify|invalid|drut|optional> <input> [output]")
	}
	switch os.Args[1] {
	case "optional":
		optional()
	case "check":
		if len(os.Args) != 4 {
			fail("usage: interop check <messages.json> <out.json>")
		}
		check(os.Args[2:])
	case "verify":
		if len(os.Args) != 3 {
			fail("usage: interop verify <in.json>")
		}
		verify(os.Args[2:])
	case "invalid":
		if len(os.Args) != 3 {
			fail("usage: interop invalid <invalid.json>")
		}
		invalid(os.Args[2:])
	case "drut":
		if len(os.Args) != 5 {
			fail("usage: interop drut <valid.json> <invalid.json> <out.json>")
		}
		drut(os.Args[2], os.Args[3], os.Args[4])
	default:
		fail("unknown mode " + os.Args[1])
	}
}