"""Writes messages.jsonl, the labelled test set.

Every message here is synthetic: written to look like the M-Pesa SMS a chama treasurer
receives, using the made-up members of EvalChama. None is a real message. Run it again
after editing to regenerate the file: python3 make_messages.py > messages.jsonl
"""
import json
import random

rng = random.Random(7)
used = {"TKA1B2C3D4"}


def code():
    while True:
        c = "TK" + "".join(rng.choice("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789") for _ in range(8))
        if any(ch.isdigit() for ch in c[2:]) and c not in used:
            used.add(c)
            return c


def received(c, amount, name, phone, date, time, balance):
    return (f"{c} Confirmed.You have received Ksh{amount} from {name} {phone} on {date} at {time} "
            f"New M-PESA balance is Ksh{balance}.")


cases = []


def add(id, kind, text, expect, member=None, amount=None, receipt=None, cycle=None):
    row = {"id": id, "kind": kind, "text": text, "expect": expect}
    if expect == "record":
        row.update(member=member, amount=amount, receipt=receipt, cycle=cycle)
    cases.append(row)


# Standard "You have received" SMS with the member's full number.
standard = [
    ("Wanjiru Njoroge", "WANJIRU NJOROGE", "0712345678", "2,000.00", "1/11/26", "8:14 AM", "4,000.00"),
    ("Amina Wanjiku", "AMINA WANJIKU", "0733000222", "2,000.00", "2/11/26", "7:42 PM", "6,000.00"),
    ("Grace Wanjiku", "GRACE WANJIKU", "0711222333", "2,000.00", "3/11/26", "12:05 PM", "8,000.00"),
    ("Brian Otieno", "BRIAN OTIENO", "0744000333", "2,000.00", "4/11/26", "9:30 PM", "10,000.00"),
    ("Peter Kamau", "PETER KAMAU", "0720456789", "2,000.00", "5/11/26", "6:01 AM", "12,000.00"),
    ("Mary Achieng", "MARY ACHIENG", "0790123456", "2,000.00", "6/11/26", "1:18 PM", "14,000.00"),
    ("Faith Chebet", "FAITH CHEBET", "0115678901", "2,000.00", "7/11/26", "5:55 PM", "16,000.00"),
    ("Kevin Mutua", "KEVIN MUTUA", "0701987654", "2,000.00", "8/11/26", "10:10 AM", "18,000.00"),
    ("Esther Nyambura", "ESTHER NYAMBURA", "0728334455", "2,000.00", "9/11/26", "8:47 PM", "20,000.00"),
    ("Amina Wanjiku", "AMINA WANJIKU", "0733000222", "500.00", "10/11/26", "7:03 PM", "20,500.00"),
]
for i, (member, name, phone, amount, date, time, balance) in enumerate(standard, 1):
    c = code()
    add(f"standard-{i:02}", "standard", received(c, amount, name, phone, date, time, balance),
        "record", member, amount.replace(",", ""), c, 10)

# Received amount equals the new balance (the account was empty): both mentions are the same number.
c = code()
add("standard-11", "standard", received(c, "2,000.00", "KEVIN MUTUA", "0701987654", "11/11/26", "7:00 AM", "2,000.00"),
    "record", "Kevin Mutua", "2000.00", c, 10)

# Newer-style masked numbers: the name has to do some of the work.
masked = [
    ("Amina Wanjiku", "AMINA WANJIKU", "0733***222"),
    ("Grace Wanjiku", "GRACE WANJIKU", "0711***333"),
    ("Brian Otieno", "BRIAN OTIENO", "0744***333"),
    ("Faith Chebet", "FAITH CHEBET", "0115***901"),
    ("Kevin Mutua", "KEVIN MUTUA", "0701***654"),
    ("Grace Wanjiku", "G WANJIKU", "0711***333"),
]
for i, (member, name, phone) in enumerate(masked, 1):
    c = code()
    add(f"masked-{i:02}", "masked-phone", received(c, "2,000.00", name, phone, f"{11 + i}/11/26", "6:20 PM", "9,000.00"),
        "record", member, "2000.00", c, 10)

# Only a surname and an unusable mask: two members fit, so a person decides.
add("ambiguous-01", "ambiguous", received(code(), "2,000.00", "WANJIKU", "07******22", "18/11/26", "9:12 AM", "11,000.00"), "check")
add("ambiguous-02", "ambiguous", received(code(), "1,000.00", "OTIENO", "07******33", "18/11/26", "9:40 AM", "12,000.00"), "check")

# Sender is not a member and nothing says who it is for.
add("unknown-01", "unknown-sender", received(code(), "2,000.00", "JAMES KARIUKI", "0799111222", "19/11/26", "3:33 PM", "14,000.00"), "check")
add("unknown-02", "bank-transfer",
    f"{code()} Confirmed.You have received Ksh2,000.00 from Equity Bulk Account 300600 on 19/11/26 at 4:02 PM New M-PESA balance is Ksh16,000.00.", "check")

# Someone else paid, and the forwarded note says for whom.
behalf = [
    ("Mary Achieng", "Hii ni ya Mary Achieng\n", "JAMES KARIUKI", "0799111222"),
    ("Kevin Mutua", "For Kevin Mutua's contribution\n", "ANN MUTUA", "0700111222"),
    ("Esther Nyambura", "Esther's November chama 👇\n", "SAMUEL NYAMBURA", "0711000999"),
]
for i, (member, note, name, phone) in enumerate(behalf, 1):
    c = code()
    add(f"behalf-{i:02}", "paid-for-someone", note + received(c, "2,000.00", name, phone, f"{19 + i}/11/26", "8:00 PM", "18,000.00"),
        "record", member, "2000.00", c, 10)

# A member's own message is a claim, not proof: the treasurer checks M-Pesa first.
add("note-01", "member-note", f"Nimetuma 2k ya November, code {code()}. Amina", "check")
add("note-02", "member-note", f"Hi treasurer, sent 2,000 for Nov. Ref {code()} - Peter Kamau", "check")
add("note-03", "member-note", "Nimelipa elfu mbili leo asubuhi. Faith", "check")
add("note-04", "member-note", "Sent you 1500 today, will top up 500 next week. Brian", "check")
add("note-05", "member-note", f"Kevin: {code()} 2000 chama", "check")

# Not money coming in.
skip = [
    ("sent", f"{code()} Confirmed. Ksh500.00 sent to BRIAN OTIENO 0744000333 on 5/11/26 at 6:10 PM. New M-PESA balance is Ksh8,200.00. Transaction cost, Ksh7.00."),
    ("sent", f"{code()} Confirmed. Ksh2,000.00 sent to MARY ACHIENG 0790123456 on 6/11/26 at 2:00 PM. New M-PESA balance is Ksh6,200.00. Transaction cost, Ksh23.00."),
    ("paybill", f"{code()} Confirmed. Ksh1,200.00 sent to KPLC PREPAID for account 54301234567 on 7/11/26 at 9:02 AM New M-PESA balance is Ksh5,000.00. Transaction cost, Ksh0.00."),
    ("buy-goods", f"{code()} Confirmed. Ksh350.00 paid to NAIVAS SUPERMARKET. on 8/11/26 at 1:15 PM.New M-PESA balance is Ksh4,650.00. Transaction cost, Ksh0.00."),
    ("withdrawal", f"{code()} Confirmed.on 9/11/26 at 10:20 AMWithdraw Ksh3,000.00 from 123456 - KAMAU AGENCIES Kiambu Rd New M-PESA balance is Ksh1,650.00."),
    ("airtime", f"{code()} confirmed.You bought Ksh100.00 of airtime on 10/11/26 at 7:05 AM.New M-PESA balance is Ksh1,550.00."),
    ("airtime", f"{code()} confirmed.You bought Ksh50.00 of airtime for 254720456789 on 10/11/26 at 7:09 AM.New M-PESA balance is Ksh1,500.00."),
    ("fuliza", f"{code()} Confirmed. Fuliza M-PESA amount is Ksh 250.00. Interest charged Ksh2.50. Total Fuliza M-PESA outstanding amount is Ksh252.50 due on 12/12/26."),
    ("m-shwari", f"{code()} Confirmed.Ksh2,000.00 transferred from M-Shwari account on 12/11/26 at 4:40 PM. M-Shwari balance is Ksh10,000.00 .M-PESA balance is Ksh3,500.00 ."),
    ("reversal", f"{code()} Confirmed. Transaction {code()} has been reversed. Your account balance is now Ksh3,500.00."),
    ("balance", f"{code()} Confirmed. Your account balance was: M-PESA Account : Ksh3,500.00 on 13/11/26 at 8:00 AM."),
    ("chat", "Meeting ni Jumamosi saa nane kwa Wanjiru. Kuja na michango ya November."),
    ("chat", "Reminder: contributions of Ksh2,000 are due by the 5th. Late fee Ksh200."),
]
for i, (kind, text) in enumerate(skip, 1):
    add(f"skip-{i:02}", kind, text, "skip")

# Already in the books.
add("duplicate-01", "duplicate", received("TKA1B2C3D4", "2,000.00", "PETER KAMAU", "0720456789", "27/10/26", "7:30 PM", "7,000.00"), "check")

# Copied badly: wrapped lines, lower case, a WhatsApp forward header, no spaces.
c = code()
add("mangled-01", "wrapped", f"{c} Confirmed.You have\nreceived Ksh2,000.00 from\nPETER KAMAU 0720456789 on\n14/11/26 at 6:30 PM New\nM-PESA balance is Ksh9,100.00.",
    "record", "Peter Kamau", "2000.00", c, 10)
c = code()
add("mangled-02", "lower-case", received(c, "2,000.00", "mary achieng", "0790123456", "14/11/26", "7:45 PM", "11,100.00").lower().replace(c.lower(), c),
    "record", "Mary Achieng", "2000.00", c, 10)
c = code()
add("mangled-03", "whatsapp-forward", "[14/11, 21:02] John Otieno: " + received(c, "2,000.00", "ESTHER NYAMBURA", "0728334455", "14/11/26", "9:01 PM", "13,100.00"),
    "record", "Esther Nyambura", "2000.00", c, 10)
c = code()
add("mangled-04", "no-spaces", received(c, "2,000.00", "WANJIRU NJOROGE", "0712345678", "15/11/26", "6:00 AM", "15,100.00").replace(" ", "", 3),
    "record", "Wanjiru Njoroge", "2000.00", c, 10)

# Swahili SMS.
swahili = [
    ("Mary Achieng", "MARY ACHIENG", "0790123456"),
    ("Kevin Mutua", "KEVIN MUTUA", "0701***654"),
    ("Esther Nyambura", "ESTHER NYAMBURA", "0728334455"),
]
for i, (member, name, phone) in enumerate(swahili, 1):
    c = code()
    add(f"swahili-{i:02}", "swahili",
        f"{c} Imethibitishwa. Umepokea Ksh2,000.00 kutoka {name} {phone} tarehe {15 + i}/11/26 saa 8:12 PM. Salio lako jipya la M-PESA ni Ksh17,100.00.",
        "record", member, "2000.00", c, 10)

# The date decides the cycle: late October is cycle 9; 12:30 AM on 1 November is cycle 10 in Nairobi.
c = code()
add("date-01", "date", received(c, "2,000.00", "FAITH CHEBET", "0115678901", "28/10/26", "9:15 PM", "5,000.00"),
    "record", "Faith Chebet", "2000.00", c, 9)
c = code()
add("date-02", "date", received(c, "2,000.00", "KEVIN MUTUA", "0701987654", "1/11/26", "12:30 AM", "7,000.00"),
    "record", "Kevin Mutua", "2000.00", c, 10)

for row in cases:
    print(json.dumps(row, ensure_ascii=False))
