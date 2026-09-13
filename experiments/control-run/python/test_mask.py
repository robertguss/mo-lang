import unittest

from mask import mask_card_numbers


class MaskTest(unittest.TestCase):
    def test_sixteen_digits_become_stars(self) -> None:
        self.assertEqual(mask_card_numbers("/api/cards/4111111111111111/charge"), "/api/cards/" + "*" * 16 + "/charge")

    def test_longer_runs_are_masked_whole(self) -> None:
        self.assertEqual(mask_card_numbers("/x/1234567890123456789"), "/x/" + "*" * 19)

    def test_fifteen_digits_are_kept(self) -> None:
        self.assertEqual(mask_card_numbers("/orders/123456789012345"), "/orders/123456789012345")

    def test_every_run_is_masked(self) -> None:
        masked = mask_card_numbers("/a/5500000000000004/b/4111111111111111")
        self.assertEqual(masked, "/a/" + "*" * 16 + "/b/" + "*" * 16)

    def test_length_is_preserved(self) -> None:
        text = "/p/00001111222233334444?q=9"
        self.assertEqual(len(mask_card_numbers(text)), len(text))


if __name__ == "__main__":
    unittest.main()
