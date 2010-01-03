-- MySQL dump 10.13  Distrib 5.1.37, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: govtrack
-- ------------------------------------------------------
-- Server version	5.1.37-1ubuntu5

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `billevents`
--

DROP TABLE IF EXISTS `billevents`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `billevents` (
  `session` int(11) NOT NULL DEFAULT '0',
  `type` varchar(2) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `number` int(11) NOT NULL DEFAULT '0',
  `date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `eventxml` text COLLATE utf8_unicode_ci NOT NULL,
  KEY `bill` (`session`,`type`,`number`),
  KEY `index` (`date`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billindex`
--

DROP TABLE IF EXISTS `billindex`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `billindex` (
  `session` int(11) NOT NULL DEFAULT '0',
  `type` varchar(2) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `number` int(11) NOT NULL DEFAULT '0',
  `idx` enum('sponsor','cosponsor','crs','publiclawnumber','committee') COLLATE utf8_unicode_ci NOT NULL,
  `value` varchar(200) COLLATE utf8_unicode_ci NOT NULL,
  KEY `session` (`session`,`type`,`number`,`idx`),
  KEY `index` (`idx`,`value`(127),`session`),
  KEY `session_2` (`session`,`idx`,`value`(32))
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billlinks`
--

DROP TABLE IF EXISTS `billlinks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `billlinks` (
  `session` int(11) NOT NULL DEFAULT '0',
  `type` varchar(2) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `number` int(11) NOT NULL DEFAULT '0',
  `source` varchar(20) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `url` text COLLATE utf8_unicode_ci,
  `excerpt` text COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`session`,`type`,`number`,`source`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billlinks2`
--

DROP TABLE IF EXISTS `billlinks2`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `billlinks2` (
  `session` int(11) NOT NULL DEFAULT '0',
  `type` varchar(2) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `number` int(11) NOT NULL DEFAULT '0',
  `url` text COLLATE utf8_unicode_ci,
  `title` text COLLATE utf8_unicode_ci NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY `session` (`session`,`type`,`number`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billstatus`
--

DROP TABLE IF EXISTS `billstatus`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `billstatus` (
  `session` int(11) NOT NULL DEFAULT '0',
  `type` varchar(2) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `number` int(11) NOT NULL DEFAULT '0',
  `title` text COLLATE utf8_unicode_ci NOT NULL,
  `fulltitle` text COLLATE utf8_unicode_ci NOT NULL,
  `statusdate` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `statusxml` text COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`session`,`type`,`number`),
  KEY `fulltitle` (`fulltitle`(100)),
  KEY `statusdate` (`statusdate`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billtitles`
--

DROP TABLE IF EXISTS `billtitles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `billtitles` (
  `session` int(11) NOT NULL DEFAULT '0',
  `type` varchar(2) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `number` int(11) NOT NULL DEFAULT '0',
  `title` text COLLATE utf8_unicode_ci NOT NULL,
  `titletype` enum('official','short','popular') COLLATE utf8_unicode_ci NOT NULL,
  KEY `title` (`title`(60)),
  KEY `bill` (`session`,`type`,`number`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billusc`
--

DROP TABLE IF EXISTS `billusc`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `billusc` (
  `session` int(11) NOT NULL,
  `type` varchar(2) NOT NULL,
  `number` int(11) NOT NULL,
  `ref` varchar(30) NOT NULL,
  KEY `bill` (`session`,`type`,`number`),
  KEY `ref` (`ref`,`session`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `linksubmission`
--

DROP TABLE IF EXISTS `linksubmission`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `linksubmission` (
  `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `bill` tinytext NOT NULL,
  `url` text NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `monitormatrix`
--

DROP TABLE IF EXISTS `monitormatrix`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `monitormatrix` (
  `monitor1` text NOT NULL,
  `monitor2` text NOT NULL,
  `count` int(11) NOT NULL,
  `tfidf` float NOT NULL,
  PRIMARY KEY (`monitor1`(127),`monitor2`(127)),
  KEY `monitor1` (`monitor1`(11),`count`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `notes`
--

DROP TABLE IF EXISTS `notes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `notes` (
  `pageid` varchar(256) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `xhtml` text CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  PRIMARY KEY (`pageid`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `questions`
--

DROP TABLE IF EXISTS `questions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `questions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `question` int(11) NOT NULL,
  `submissiondate` datetime NOT NULL,
  `status` enum('new','approved','rejected') NOT NULL DEFAULT 'new',
  `approvaldate` datetime NOT NULL,
  `text` text NOT NULL,
  `topic` text NOT NULL,
  `moderator` varchar(12) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `question` (`question`),
  KEY `topic` (`topic`(16))
) ENGINE=MyISAM AUTO_INCREMENT=26498 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `votes`
--

DROP TABLE IF EXISTS `votes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `votes` (
  `id` varchar(10) COLLATE utf8_unicode_ci NOT NULL,
  `date` datetime NOT NULL,
  `description` text COLLATE utf8_unicode_ci NOT NULL,
  `result` text COLLATE utf8_unicode_ci NOT NULL,
  `billsession` int(11) DEFAULT NULL,
  `billtype` varchar(2) COLLATE utf8_unicode_ci DEFAULT NULL,
  `billnumber` int(11) DEFAULT NULL,
  `amdtype` char(1) COLLATE utf8_unicode_ci DEFAULT NULL,
  `amdnumber` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `bill` (`billsession`,`billtype`,`billnumber`),
  KEY `date` (`date`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2010-01-03 17:28:17
