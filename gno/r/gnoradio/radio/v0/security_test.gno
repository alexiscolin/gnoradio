package radio

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/gnoradio/catalog/v0"
)

// Y1: a genre edit must not leave a slot in the old genre station.
func TestGenreEditLeavesNoOrphanSlot(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("genreartist")))
	catalog.RegisterArtist(cross(cur), "Genre Mover", "")
	id := publish(cur, "Mover", 3, "2:00")
	Sync(cross(cur), 50)
	i, ok := stations[3].slotOf.Get(key(id)).(int)
	urequire.True(t, ok)

	catalog.EditTrack(cross(cur), id, "Mover", 7, "2:00", "", "ipfs://"+cid, "", "", "")
	Refresh(cross(cur), id)

	_, d := stations[3].rot.Slot(i)
	uassert.Equal(t, int64(0), d) // silent on the old genre station
	j, ok := stations[7].slotOf.Get(key(id)).(int)
	urequire.True(t, ok) // now rotates on the new one
	_, d = stations[7].rot.Slot(j)
	uassert.Equal(t, int64(120), d)
	nowID, _, _ := NowPlaying(3)
	uassert.NotEqual(t, id, nowID)
}

// Y1: admin DropSlot and Unqueue.
func TestDropSlotAndUnqueue(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("dropartist")))
	catalog.RegisterArtist(cross(cur), "Drop Artist", "")
	a := publish(cur, "Drop A", 6, "1:00")
	b := publish(cur, "Drop B", 6, "1:00")
	Sync(cross(cur), 50)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("droplistener")))
	Queue(cross(cur), 6, b)
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { DropSlot(cross(cur), 6, a) })
	uassert.AbortsWithMessage(t, cur, "radio: admin only", func() { Unqueue(cross(cur), 6, b) })

	testing.SetRealm(testing.NewUserRealm(erin))
	Unqueue(cross(cur), 6, b)
	uassert.Equal(t, 0, len(UpNext(6)))
	DropSlot(cross(cur), 6, a)
	i := stations[6].slotOf.Get(key(a)).(int)
	_, d := stations[6].rot.Slot(i)
	uassert.Equal(t, int64(0), d)
	uassert.False(t, strings.Contains(ScheduleJSON(6, 600), `"track":`+itoa(a)+`,`))
	uassert.AbortsContains(t, cur, "not in this station", func() { DropSlot(cross(cur), 9, a) })
}

// Y6: one queue per station per hour per wallet, and at most 2 hours ahead.
func TestQueueCooldownAndAirtimeCap(cur realm, t *testing.T) {
	reset()
	var ids []int
	for i := 0; i < 10; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("longartist" + itoa(i))))
		catalog.RegisterArtist(cross(cur), "Long Artist "+itoa(i), "")
		ids = append(ids, publish(cur, "Long "+itoa(i), 8, "19:00"))
	}
	Sync(cross(cur), 50)

	fan := testutils.TestAddress("cooldownfan")
	testing.SetRealm(testing.NewUserRealm(fan))
	Queue(cross(cur), 8, ids[0])
	testing.SkipHeights(300) // 25 min later: the slot started, nothing is waiting
	uassert.AbortsContains(t, cur, "one track per station per hour", func() { Queue(cross(cur), 8, ids[1]) })

	// Distinct wallets, distinct artists: 19-minute tracks hit the 2-hour cap.
	capped := false
	for i := 1; i < 10 && !capped; i++ {
		who := testutils.TestAddress("filler" + itoa(i))
		func() {
			defer func() {
				if r := recover(); r != nil {
					msg, _ := r.(string)
					urequire.True(t, strings.Contains(msg, "two hours ahead"), msg)
					capped = true
				}
			}()
			queue(who, 8, ids[i], false)
		}()
	}
	urequire.True(t, capped)
	// Curators are exempt from the cap.
	testing.SetRealm(testing.NewUserRealm(erin))
	CuratorQueue(cross(cur), 8, ids[9])
}
