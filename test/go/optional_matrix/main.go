// One endpoint of the cross-language optional-field exchange for Go.
//
//   optional_matrix produce CASES_JSON OUT_JSON : encode each canonical
//       optional case through the public `OptionalBoxToDrut`.
//   optional_matrix consume PEER_JSON           : decode a peer's encodings
//       through the public `OptionalBoxFromDrut`, check the typed field states
//       (including the nil pointer versus pointer to an empty slice) and
//       re-encode the same Drut.

package main

import (
	"encoding/json"
	"fmt"
	"os"

	"generated_contracts/api"
)

type entry struct {
	ID   string `json:"id"`
	Wire string `json:"wire"`
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, "FAIL: "+message)
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

func cases() []struct {
	id  string
	box api.OptionalBox
} {
	text := ""
	count := 0
	flag := false
	items := []string{}
	var textChoice api.Choice = api.ChoiceText{Value: "x"}
	var voidChoice api.Choice = api.ChoiceEmpty{}
	return []struct {
		id  string
		box api.OptionalBox
	}{
		{"absent", api.OptionalBox{OwnerID: "o1"}},
		{"empty_string", api.OptionalBox{OwnerID: "o1", Text: &text}},
		{"zero", api.OptionalBox{OwnerID: "o1", Count: &count}},
		{"false", api.OptionalBox{OwnerID: "o1", Flag: &flag}},
		{"empty_list", api.OptionalBox{OwnerID: "o1", Items: &items}},
		{"variant_text", api.OptionalBox{OwnerID: "o1", Choice: &textChoice}},
		{"variant_void", api.OptionalBox{OwnerID: "o1", Choice: &voidChoice}},
		{"all_present", api.OptionalBox{
			OwnerID: "o1", Text: &text, Count: &count, Flag: &flag,
			Items: &items, Choice: &voidChoice,
		}},
	}
}

func checkSemantics(id string, value api.OptionalBox) {
	none := func(values ...any) bool {
		for _, value := range values {
			switch typed := value.(type) {
			case *string:
				if typed != nil {
					return false
				}
			case *int:
				if typed != nil {
					return false
				}
			case *bool:
				if typed != nil {
					return false
				}
			case *[]string:
				if typed != nil {
					return false
				}
			case *api.Choice:
				if typed != nil {
					return false
				}
			}
		}
		return true
	}
	var expected bool
	switch id {
	case "absent":
		expected = none(value.Text, value.Count, value.Flag, value.Items, value.Choice)
	case "empty_string":
		expected = value.Text != nil && *value.Text == "" &&
			none(value.Count, value.Flag, value.Items, value.Choice)
	case "zero":
		expected = value.Count != nil && *value.Count == 0 &&
			none(value.Text, value.Flag, value.Items, value.Choice)
	case "false":
		expected = value.Flag != nil && *value.Flag == false &&
			none(value.Text, value.Count, value.Items, value.Choice)
	case "empty_list":
		expected = value.Items != nil && len(*value.Items) == 0 &&
			none(value.Text, value.Count, value.Flag, value.Choice)
	case "variant_text":
		if value.Choice != nil {
			payload, ok := (*value.Choice).(api.ChoiceText)
			expected = ok && payload.Value == "x"
		}
		expected = expected && none(value.Text, value.Count, value.Flag, value.Items)
	case "variant_void":
		if value.Choice != nil {
			_, ok := (*value.Choice).(api.ChoiceEmpty)
			expected = ok
		}
		expected = expected && none(value.Text, value.Count, value.Flag, value.Items)
	case "all_present":
		_, void := (*value.Choice).(api.ChoiceEmpty)
		expected = value.Text != nil && *value.Text == "" &&
			value.Count != nil && *value.Count == 0 &&
			value.Flag != nil && *value.Flag == false &&
			value.Items != nil && len(*value.Items) == 0 &&
			value.Choice != nil && void
	default:
		fail("unknown case " + id)
	}
	if !expected {
		fail("case " + id + " decoded to the wrong typed value")
	}
}

func produce(casesPath, outPath string) {
	canonical := map[string]string{}
	for _, item := range readEntries(casesPath) {
		canonical[item.ID] = item.Wire
	}
	results := make([]entry, 0, len(cases()))
	for _, item := range cases() {
		wire, err := api.OptionalBoxToDrut(item.box)
		if err != nil {
			fail(item.id + ": " + err.Error())
		}
		want, ok := canonical[item.id]
		if !ok {
			fail("no canonical wire for case " + item.id)
		}
		if want != wire {
			fail(item.id + ": encoded " + wire + ", expected " + want)
		}
		results = append(results, entry{ID: item.id, Wire: wire})
	}
	output, err := json.MarshalIndent(results, "", "  ")
	if err != nil {
		fail(err.Error())
	}
	if err := os.WriteFile(outPath, output, 0o644); err != nil {
		fail(err.Error())
	}
	fmt.Printf("go produced %d optional case(s)\n", len(results))
}

func consume(peerPath string) {
	entries := readEntries(peerPath)
	for _, item := range entries {
		value, err := api.OptionalBoxFromDrut(item.Wire)
		if err != nil {
			fail(item.ID + ": " + err.Error())
		}
		checkSemantics(item.ID, value)
		reencoded, err := api.OptionalBoxToDrut(value)
		if err != nil {
			fail(item.ID + ": " + err.Error())
		}
		if reencoded != item.Wire {
			fail(item.ID + ": re-encoded " + reencoded + ", received " + item.Wire)
		}
	}
	fmt.Printf("go consumed %d optional case(s)\n", len(entries))
}

func main() {
	if len(os.Args) < 3 {
		fail("usage: optional_matrix <produce|consume> INPUT [OUT]")
	}
	switch os.Args[1] {
	case "produce":
		if len(os.Args) != 4 {
			fail("usage: optional_matrix produce CASES_JSON OUT_JSON")
		}
		produce(os.Args[2], os.Args[3])
	case "consume":
		if len(os.Args) != 3 {
			fail("usage: optional_matrix consume PEER_JSON")
		}
		consume(os.Args[2])
	default:
		fail("unknown mode " + os.Args[1])
	}
}