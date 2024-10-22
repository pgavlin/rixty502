package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/akif999/srec"
)

func main() {
	start := flag.Uint("start", 0, "start address")

	sr := srec.NewSrec()
	if err := sr.Parse(os.Stdin); err != nil {
		log.Fatal("parsing srec: %w", err)
	}

	fmt.Println(`.segment "PROGRAM"`)
	fmt.Println(`program:`)
	if *start != 0 {
		fmt.Printf("\t.org $%x\n", *start)
	}

	where := uint32(*start)
	for _, rec := range sr.Records {
		switch rec.Srectype {
		case "S1", "S2", "S3":
		default:
			continue
		}
		if rec.Address != where {
			where = rec.Address
			fmt.Printf("\t.org $%04x\n", where)
		}

		if len(rec.Data) != 0 {
			fmt.Printf("\t.byte ")
			for i, b := range rec.Data {
				if i > 0 {
					fmt.Printf(", ")
				}
				fmt.Printf("$%02x", b)
			}
			fmt.Println()
		}

		where += uint32(len(rec.Data))
	}

	fmt.Println()
	fmt.Println(`.export program`)
}
