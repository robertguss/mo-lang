import unittest

from logstat.mask import find_card_number, mask_card_numbers


class MaskTest(unittest.TestCase):
    def test_masks_sixteen_digits(self) -> None:
        self.assertEqual(mask_card_numbers("/pay/4111111111111111"), "/pay/" + "*" * 16)

    def test_masks_a_dashed_card_number(self) -> None:
        self.assertEqual(mask_card_numbers("/pay/4111-1111-1111-1111"), "/pay/****-****-****-****")

    def test_masks_a_longer_run_whole(self) -> None:
        self.assertEqual(mask_card_numbers("/x/12345678901234567"), "/x/" + "*" * 17)

    def test_masks_every_card_number(self) -> None:
        masked = mask_card_numbers("/a/4111111111111111/b/5500000000000004")
        self.assertIsNone(find_card_number(masked))
        self.assertEqual(masked.count("*"), 32)

    def test_leaves_short_digit_runs(self) -> None:
        for text in ("/orders/123456789012345", "/day/2026-09-12", "/a/7"):
            self.assertEqual(mask_card_numbers(text), text)

    def test_find_card_number(self) -> None:
        self.assertEqual(find_card_number("x4111111111111111y"), "4111111111111111")
        self.assertIsNone(find_card_number("x411111111111111y"))


if __name__ == "__main__":
    unittest.main()
