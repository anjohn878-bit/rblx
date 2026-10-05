local Harness = ...
local Format = Harness.require(Harness.Shared.Util.Format)
local eq = Harness.eq

eq(Format.Commas(0), "0", "Commas(0)")
eq(Format.Commas(999), "999", "Commas(999)")
eq(Format.Commas(1250), "1,250", "Commas(1250)")
eq(Format.Commas(1234567), "1,234,567", "Commas(1234567)")
eq(Format.Commas(-4500), "-4,500", "Commas(-4500)")
eq(Format.Short(99999), "99,999", "Short(99999)")
eq(Format.Short(100000), "100K", "Short(100000)")
eq(Format.Short(1250000), "1.25M", "Short(1.25M)")
eq(Format.Short(12500000), "12.5M", "Short(12.5M)")
eq(Format.Short(2000000000), "2.00B", "Short(2B)")
eq(Format.Money(12450), "$12,450", "Money(12450)")
eq(Format.Time(75), "1m 15s", "Time(75)")
