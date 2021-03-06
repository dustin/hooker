{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import           Test.QuickCheck            (Arbitrary, arbitrary)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck      as QC

import qualified Data.Attoparsec.ByteString as A
import qualified Data.ByteString.Lazy       as BL
import           Data.Semigroup             ((<>))
import qualified Data.Set                   as Set
import           Data.Text                  (Text, pack)
import           Data.Time                  (Day (..))

import           Processor

instance Arbitrary HourStamp where
  arbitrary = HourStamp <$> (ModifiedJulianDay <$> arbitrary) <*> choose (0, 23)

instance Arbitrary EventType where
  arbitrary = arbitraryBoundedEnum

instance Arbitrary Repo where
  arbitrary = Repo <$> arbitrary <*> (pack <$> arbitrary) <*> pure mempty

data EnumIDer = PlusMinus | MinusPlus | FromTo | ID deriving (Enum, Bounded, Show)

evalEnumIDer :: Enum a => EnumIDer -> a -> a
evalEnumIDer PlusMinus = pred.succ
evalEnumIDer MinusPlus = succ.pred
evalEnumIDer FromTo    = toEnum.fromEnum
evalEnumIDer ID        = id

instance Arbitrary EnumIDer where arbitrary = arbitraryBoundedEnum

enumEvalID :: (Enum a, Eq a) => EnumIDer -> a -> Bool
enumEvalID f = evalEnumIDer f >>= (==)

parseOne :: Assertion
parseOne = do
  let d = "{\"id\":\"7375355128\",\"type\":\"PushEvent\",\"actor\":{\"id\":12688150,\"login\":\"Aree-Vanier\",\"display_login\":\"Aree-Vanier\",\"gravatar_id\":\"\",\"url\":\"https://api.github.com/users/Aree-Vanier\",\"avatar_url\":\"https://avatars.githubusercontent.com/u/12688150?\"},\"repo\":{\"id\":118478081,\"name\":\"Aree-Vanier/Private-Voting-Bot\",\"url\":\"https://api.github.com/repos/Aree-Vanier/Private-Voting-Bot\"},\"payload\":{\"push_id\":2400550176,\"size\":2,\"distinct_size\":2,\"ref\":\"refs/heads/master\",\"head\":\"ec88a27a36353c3413fe8ab995c8cf8b940b22f4\",\"before\":\"5070b0b3a0f249cab4cb8cca083c0258f6f0dfcf\",\"commits\":[{\"sha\":\"77851f9bc893101c5629b22df5b5178ae9fa2785\",\"author\":{\"name\":\"Aree-Vanier\",\"email\":\"103febca8282301c88d7014bf9446121ad7f52c3@ajayinkingston.com\"},\"message\":\"Documented vote sorting code\",\"distinct\":true,\"url\":\"https://api.github.com/repos/Aree-Vanier/Private-Voting-Bot/commits/77851f9bc893101c5629b22df5b5178ae9fa2785\"},{\"sha\":\"ec88a27a36353c3413fe8ab995c8cf8b940b22f4\",\"author\":{\"name\":\"Aree-Vanier\",\"email\":\"103febca8282301c88d7014bf9446121ad7f52c3@ajayinkingston.com\"},\"message\":\"Updated readme\",\"distinct\":true,\"url\":\"https://api.github.com/repos/Aree-Vanier/Private-Voting-Bot/commits/ec88a27a36353c3413fe8ab995c8cf8b940b22f4\"}]},\"public\":true,\"created_at\":\"2018-03-14T00:00:00Z\"}"
  case A.parseOnly parseEvent d of
    (Left x)              -> assertFailure (show x)
    (Right (Repo et _ _)) -> assertEqual "event type" et PushEvent

parseSample :: (Repo -> Bool) -> Int -> Assertion
parseSample f l = do
  d <- BL.readFile "test/small.gz"
  case filter f <$> processStream d of
    (Left x)  -> assertFailure (show x)
    (Right x) -> length x @?= l

interestingRepos :: Set.Set Text
interestingRepos = Set.fromList [
  "dotclear/dotclear",
  "google-test2/signcla-probe-repo",
  "fxtools/quote_percentages"
  ]

allTrueIsTrue :: [Bool] -> Bool
allTrueIsTrue l = combineFilters (map const l) undefined == and l

combineShortCircuitsProp :: [Bool] -> Bool
combineShortCircuitsProp l = not $ combineFilters (map const (l <> [False, undefined])) undefined

typeIsProp :: EventType -> Bool
typeIsProp et = typeIs et (Repo et mempty mempty)

typeIsProp2 :: EventType -> Repo -> Bool
typeIsProp2 et r@(Repo et' _ _) = typeIs et r == (et == et')

roundtripProp :: (Show a, Read a, Eq a) => a -> Bool
roundtripProp = read.show >>= (==)


tests :: [TestTree]
tests = [
  testProperty "hour stamp enum +- identity" (enumEvalID :: EnumIDer -> HourStamp -> Bool),
  testProperty "combine filters is true for all" allTrueIsTrue,
  testProperty "combined filters short circuits" combineShortCircuitsProp,
  testProperty "typeIs works" typeIsProp,
  testProperty "typeIs works 2" typeIsProp2,

  testProperty "hourstamp round trips" (roundtripProp :: HourStamp -> Bool),

  testCase "parse one literal" parseOne,
  testCase "parse small sample" $ parseSample (const True) 10000,
  testCase "parse pushes from sample" $ parseSample (\(Repo t _ _) -> t == PushEvent) 5738,
  testCase "parse interesting sample" $ parseSample (interestingFilter interestingRepos) 86
  ]

main :: IO ()
main = defaultMain $ testGroup "All Tests" tests
