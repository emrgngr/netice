import '../l10n/l10n.dart';
import 'models.dart';

/// Ülkelere göre unvan sistemleri: akademik unvanlar, askerî ve emniyet
/// rütbeleri (adın önüne yazılır) ile kurum türüne göre görev/kadro unvanları.
/// Unvanlar o ülkenin kendi resmi dilinde tutulur; çevrilmez.
class TitleSystem {
  final String code;
  final List<String> academic;
  final List<String> military;
  final List<String> police;
  final List<String> schoolHead, schoolStaff;
  final List<String> uniHead, uniStaff;
  final List<String> milHead, milStaff;
  final List<String> polHead, polStaff;
  final List<String> genHead, genStaff;

  const TitleSystem({
    required this.code,
    required this.academic,
    required this.military,
    required this.police,
    required this.schoolHead,
    required this.schoolStaff,
    required this.uniHead,
    required this.uniStaff,
    required this.milHead,
    required this.milStaff,
    required this.polHead,
    required this.polStaff,
    required this.genHead,
    required this.genStaff,
  });

  String get countryName => switch (code) {
        'tr' => tr('Türkiye'),
        'en' => tr('İngilizce konuşulan ülkeler (ABD, Birleşik Krallık…)'),
        'de' => tr('Almanya'),
        'fr' => tr('Fransa'),
        'ru' => tr('Rusya'),
        'az' => tr('Azerbaycan'),
        'es' => tr('İspanya'),
        'it' => tr('İtalya'),
        'ar' => tr('Arap ülkeleri'),
        'zh' => tr('Çin'),
        'ja' => tr('Japonya'),
        _ => code,
      };

  static TitleSystem byCode(String? c) => all.firstWhere((s) => s.code == c, orElse: () => all.first);

  /// Uygulama diline göre varsayılan sistem.
  static String defaultCode() => all.any((s) => s.code == L10n.code) ? L10n.code : 'en';

  /// Adın önüne yazılan unvan ve rütbeler, gruplu.
  List<(String, List<String>)> prefixes(InstitutionType t) => [
        if (t == InstitutionType.military) (tr('Askerî rütbeler'), military),
        if (t == InstitutionType.police) (tr('Emniyet rütbeleri'), police),
        (tr('Akademik unvanlar'), academic),
      ];

  /// Görev unvanları: amir (head) ya da öğretim personeli.
  List<(String, List<String>)> roles(InstitutionType t, {required bool head}) {
    final (h, s) = switch (t) {
      InstitutionType.school => (schoolHead, schoolStaff),
      InstitutionType.university => (uniHead, uniStaff),
      InstitutionType.military => (milHead, milStaff),
      InstitutionType.police => (polHead, polStaff),
      _ => (genHead, genStaff),
    };
    return [
      (head ? tr('Yönetim görevleri') : tr('Öğretim görevleri'), head ? h : s),
      (head ? tr('Öğretim görevleri') : tr('Yönetim görevleri'), head ? s : h),
    ];
  }

  static const all = <TitleSystem>[
    TitleSystem(
      code: 'tr',
      academic: ['Prof. Dr.', 'Doç. Dr.', 'Dr. Öğr. Üyesi', 'Öğr. Gör. Dr.', 'Öğr. Gör.', 'Arş. Gör. Dr.', 'Arş. Gör.', 'Uzm.', 'Dr.'],
      military: [
        'Org.', 'Korg.', 'Tümg.', 'Tuğg.', 'Alb.', 'Yb.', 'Bnb.', 'Yzb.', 'Ütğm.', 'Tğm.', 'Asteğm.', //
        'Kd. Bçvş.', 'Bçvş.', 'Kd. Üçvş.', 'Üçvş.', 'Kd. Çvş.', 'Çvş.', 'Uzm. Çvş.', 'Uzm. Onb.',
        'Ora.', 'Kora.', 'Tüma.', 'Tuğa.', 'Kd. Alb.', 'Kd. Yb.', 'Kd. Bnb.', //
      ],
      police: [
        '1. Sınıf Emniyet Müdürü', '2. Sınıf Emniyet Müdürü', '3. Sınıf Emniyet Müdürü', '4. Sınıf Emniyet Müdürü',
        'Emniyet Amiri', 'Başkomiser', 'Komiser', 'Komiser Yardımcısı', 'Polis Memuru', 'Bekçi',
      ],
      schoolHead: ['Okul Müdürü', 'Müdür Başyardımcısı', 'Müdür Yardımcısı', 'Kurucu Müdür', 'Okul Müdür Vekili', 'Askerî Lise Komutanı'],
      schoolStaff: [
        'Ders Öğretmeni', 'Sınıf Öğretmeni', 'Branş Öğretmeni', 'Uzman Öğretmen', 'Başöğretmen', 'Zümre Başkanı',
        'Rehber Öğretmen (Psikolojik Danışman)', 'Sınıf Rehber Öğretmeni', 'Usta Öğretici', 'Ücretli Öğretmen',
      ],
      uniHead: [
        'Rektör', 'Rektör Yardımcısı', 'Dekan', 'Dekan Yardımcısı', 'Enstitü Müdürü', 'Yüksekokul Müdürü',
        'Meslek Yüksekokulu Müdürü', 'Müdür Yardımcısı', 'Bölüm Başkanı', 'Bölüm Başkan Yardımcısı',
        'Anabilim Dalı Başkanı', 'Program Başkanı', 'Program Koordinatörü',
      ],
      uniStaff: [
        'Öğretim Üyesi', 'Öğretim Görevlisi', 'Araştırma Görevlisi', 'Öğretim Elemanı', 'Ders Sorumlusu',
        'Danışman Öğretim Elemanı', 'Uzman',
      ],
      milHead: [
        'Rektör', 'Rektör Yardımcısı', 'Dekan', 'Harp Okulu Dekanı', 'Enstitü Müdürü', 'Okul Komutanı', 'Lise Komutanı',
        'Eğitim Merkezi Komutanı', 'Astsubay Meslek Yüksekokulu Müdürü', 'Öğretim Başkanı', 'Alay Komutanı',
        'Tabur Komutanı', 'Bölük Komutanı',
      ],
      milStaff: [
        'Öğretim Elemanı', 'Öğretim Üyesi', 'Öğretim Görevlisi', 'Öğretmen', 'Ders Öğretmeni', 'Eğitici Personel',
        'Bölük Komutanı', 'Takım Komutanı', 'Kısım Komutanı',
      ],
      polHead: [
        'Polis Akademisi Başkanı', 'Başkan Yardımcısı', 'Enstitü Müdürü', 'Fakülte Dekanı', 'Dekan Yardımcısı',
        'Polis Meslek Yüksekokulu Müdürü', 'Polis Meslek Eğitim Merkezi Müdürü', 'Müdür Yardımcısı',
        'Eğitim Öğretim Şube Müdürü', 'Bölüm Başkanı', 'Bölük Amiri',
      ],
      polStaff: [
        'Öğretim Görevlisi', 'Öğretim Üyesi', 'Öğretim Elemanı', 'Öğretmen', 'Eğitim Personeli', 'Eğitici Personel',
        'Bölük Amiri', 'Takım Amiri', 'Ders Sorumlusu',
      ],
      genHead: ['Kurum Müdürü', 'Müdür Yardımcısı', 'Kurucu', 'Genel Müdür', 'Daire Başkanı', 'Şube Müdürü', 'Eğitim Müdürü', 'Eğitim Koordinatörü'],
      genStaff: ['Eğitmen', 'Öğretmen', 'Usta Öğretici', 'Eğitim Uzmanı', 'Kurs Öğretmeni'],
    ),
    TitleSystem(
      code: 'en',
      academic: ['Prof.', 'Assoc. Prof.', 'Asst. Prof.', 'Dr.', 'Mr.', 'Ms.', 'Mrs.'],
      military: [
        'Gen.', 'Lt. Gen.', 'Maj. Gen.', 'Brig. Gen.', 'Col.', 'Lt. Col.', 'Maj.', 'Capt.', '1st Lt.', '2nd Lt.',
        'CSM', 'Sgt. Maj.', 'MSgt.', 'SFC', 'SSgt.', 'Sgt.', 'Adm.', 'Cmdr.', 'Lt. Cmdr.',
      ],
      police: ['Chief Constable', 'Chief Supt.', 'Supt.', 'Chief Insp.', 'Insp.', 'Sgt.', 'PC', 'Capt.', 'Lt.', 'Officer'],
      schoolHead: ['Principal', 'Vice Principal', 'Assistant Principal', 'Head Teacher', 'Deputy Head Teacher', 'Superintendent'],
      schoolStaff: ['Teacher', 'Class Teacher', 'Subject Teacher', 'Head of Department', 'Senior Teacher', 'School Counselor', 'Teaching Assistant'],
      uniHead: ['President', 'Vice-Chancellor', 'Provost', 'Rector', 'Dean', 'Associate Dean', 'Director', 'Head of Department', 'Program Director'],
      uniStaff: ['Professor', 'Associate Professor', 'Assistant Professor', 'Senior Lecturer', 'Lecturer', 'Instructor', 'Teaching Fellow', 'Teaching Assistant'],
      milHead: ['Commandant', 'Superintendent', 'Dean of Faculty', 'Commanding Officer', 'Director of Studies', 'Battalion Commander', 'Company Commander'],
      milStaff: ['Instructor', 'Professor', 'Lecturer', 'Training Officer', 'Drill Instructor', 'Platoon Commander'],
      polHead: ['Commandant', 'Director', 'Deputy Director', 'Principal', 'Head of Training'],
      polStaff: ['Instructor', 'Trainer', 'Lecturer', 'Field Training Officer', 'Class Supervisor'],
      genHead: ['Director', 'Deputy Director', 'Training Manager', 'Coordinator', 'Head of Training'],
      genStaff: ['Trainer', 'Instructor', 'Teacher', 'Tutor', 'Training Specialist'],
    ),
    TitleSystem(
      code: 'de',
      academic: ['Prof. Dr.', 'Prof.', 'Jun.-Prof. Dr.', 'PD Dr.', 'Dr.', 'Dipl.-Ing.', 'Herr', 'Frau'],
      military: [
        'General', 'Generalleutnant', 'Generalmajor', 'Brigadegeneral', 'Oberst', 'Oberstleutnant', 'Major',
        'Stabshauptmann', 'Hauptmann', 'Oberleutnant', 'Leutnant', 'Oberstabsfeldwebel', 'Stabsfeldwebel',
        'Hauptfeldwebel', 'Oberfeldwebel', 'Feldwebel', 'Fregattenkapitän', 'Korvettenkapitän',
      ],
      police: [
        'Polizeipräsident/in', 'Leitende/r Polizeidirektor/in', 'Polizeidirektor/in', 'Polizeioberrat/-rätin',
        'Polizeirat/-rätin', 'Erste/r Polizeihauptkommissar/in', 'Polizeihauptkommissar/in',
        'Polizeioberkommissar/in', 'Polizeikommissar/in', 'Polizeihauptmeister/in', 'Polizeiobermeister/in',
      ],
      schoolHead: ['Schulleiter/in', 'Stellv. Schulleiter/in', 'Oberstudiendirektor/in', 'Studiendirektor/in', 'Rektor/in', 'Konrektor/in'],
      schoolStaff: ['Lehrer/in', 'Klassenlehrer/in', 'Fachlehrer/in', 'Oberstudienrat/-rätin', 'Studienrat/-rätin', 'Fachbereichsleiter/in', 'Referendar/in'],
      uniHead: ['Präsident/in', 'Rektor/in', 'Vizepräsident/in', 'Kanzler/in', 'Dekan/in', 'Prodekan/in', 'Studiendekan/in', 'Institutsleiter/in'],
      uniStaff: ['Professor/in', 'Juniorprofessor/in', 'Privatdozent/in', 'Dozent/in', 'Lehrbeauftragte/r', 'Wissenschaftliche/r Mitarbeiter/in', 'Lehrkraft für besondere Aufgaben'],
      milHead: ['Kommandeur/in', 'Schulkommandeur/in', 'Präsident/in', 'Dekan/in', 'Leiter/in Lehrgruppe', 'Bataillonskommandeur/in', 'Kompaniechef/in'],
      milStaff: ['Hörsaalleiter/in', 'Lehroffizier/in', 'Ausbilder/in', 'Dozent/in', 'Professor/in', 'Zugführer/in'],
      polHead: ['Präsident/in der Polizeiakademie', 'Direktor/in', 'Leiter/in', 'Fachbereichsleiter/in', 'Studiengangsleiter/in'],
      polStaff: ['Dozent/in', 'Fachlehrer/in', 'Polizeitrainer/in', 'Lehrbeauftragte/r', 'Ausbilder/in'],
      genHead: ['Geschäftsführer/in', 'Leiter/in', 'Stellv. Leiter/in', 'Ausbildungsleiter/in', 'Koordinator/in'],
      genStaff: ['Trainer/in', 'Kursleiter/in', 'Dozent/in', 'Lehrer/in', 'Ausbilder/in'],
    ),
    TitleSystem(
      code: 'fr',
      academic: ['Pr', 'Dr', 'M.', 'Mme'],
      military: [
        'Général d’armée', 'Général de corps d’armée', 'Général de division', 'Général de brigade', 'Colonel',
        'Lieutenant-colonel', 'Commandant', 'Capitaine', 'Lieutenant', 'Sous-lieutenant', 'Major', 'Adjudant-chef',
        'Adjudant', 'Sergent-chef', 'Sergent',
      ],
      police: [
        'Commissaire général', 'Commissaire divisionnaire', 'Commissaire', 'Commandant de police', 'Capitaine de police',
        'Lieutenant de police', 'Major de police', 'Brigadier-chef', 'Brigadier', 'Gardien de la paix',
      ],
      schoolHead: ['Proviseur', 'Proviseur adjoint', 'Principal', 'Principal adjoint', 'Directeur d’école', 'Conseiller principal d’éducation'],
      schoolStaff: ['Professeur', 'Professeur agrégé', 'Professeur certifié', 'Professeur principal', 'Professeur des écoles', 'Enseignant', 'Professeur contractuel'],
      uniHead: ['Président de l’université', 'Vice-président', 'Doyen', 'Directeur de l’UFR', 'Directeur de l’IUT', 'Directeur de département', 'Responsable de formation'],
      uniStaff: ['Professeur des universités', 'Maître de conférences', 'PRAG', 'ATER', 'Chargé d’enseignement', 'Chargé de TD'],
      milHead: ['Commandant de l’école', 'Directeur général de la formation', 'Directeur des études', 'Chef de corps', 'Commandant de compagnie'],
      milStaff: ['Professeur', 'Instructeur', 'Chef de cours', 'Chef de section', 'Officier instructeur'],
      polHead: ['Directeur de l’école', 'Directeur adjoint', 'Directeur des études', 'Chef de service formation'],
      polStaff: ['Formateur', 'Enseignant', 'Instructeur', 'Moniteur', 'Chef de promotion'],
      genHead: ['Directeur', 'Directeur adjoint', 'Responsable formation', 'Coordinateur pédagogique'],
      genStaff: ['Formateur', 'Enseignant', 'Intervenant', 'Moniteur'],
    ),
    TitleSystem(
      code: 'ru',
      academic: ['проф.', 'доц.', 'д-р наук', 'канд. наук', 'акад.'],
      military: [
        'генерал-полковник', 'генерал-лейтенант', 'генерал-майор', 'полковник', 'подполковник', 'майор', 'капитан',
        'старший лейтенант', 'лейтенант', 'старший прапорщик', 'прапорщик', 'старшина', 'старший сержант', 'сержант',
      ],
      police: [
        'генерал-майор полиции', 'полковник полиции', 'подполковник полиции', 'майор полиции', 'капитан полиции',
        'старший лейтенант полиции', 'лейтенант полиции', 'старшина полиции', 'сержант полиции',
      ],
      schoolHead: ['Директор школы', 'Заместитель директора', 'Заместитель директора по учебной работе', 'Завуч'],
      schoolStaff: ['Учитель', 'Классный руководитель', 'Руководитель методического объединения', 'Педагог-психолог', 'Учитель-предметник'],
      uniHead: ['Ректор', 'Проректор', 'Декан', 'Заместитель декана', 'Директор института', 'Заведующий кафедрой'],
      uniStaff: ['Профессор', 'Доцент', 'Старший преподаватель', 'Преподаватель', 'Ассистент'],
      milHead: ['Начальник академии', 'Начальник училища', 'Начальник факультета', 'Начальник кафедры', 'Командир батальона', 'Командир роты'],
      milStaff: ['Преподаватель', 'Старший преподаватель', 'Профессор', 'Доцент', 'Командир взвода', 'Курсовой офицер'],
      polHead: ['Начальник академии', 'Начальник института', 'Начальник учебного центра', 'Заместитель начальника', 'Начальник кафедры'],
      polStaff: ['Преподаватель', 'Старший преподаватель', 'Доцент', 'Профессор', 'Инструктор'],
      genHead: ['Директор', 'Заместитель директора', 'Руководитель учебного центра', 'Методист'],
      genStaff: ['Преподаватель', 'Тренер', 'Инструктор', 'Педагог'],
    ),
    TitleSystem(
      code: 'az',
      academic: ['Prof.', 'Dos.', 'Dr.', 'Akad.'],
      military: [
        'general-leytenant', 'general-mayor', 'polkovnik', 'polkovnik-leytenant', 'mayor', 'kapitan', 'baş leytenant',
        'leytenant', 'kiçik leytenant', 'baş gizir', 'gizir', 'baş çavuş', 'çavuş',
      ],
      police: [
        'polis general-mayoru', 'polis polkovniki', 'polis polkovnik-leytenantı', 'polis mayoru', 'polis kapitanı',
        'polis baş leytenantı', 'polis leytenantı', 'polis baş çavuşu', 'polis çavuşu',
      ],
      schoolHead: ['Məktəb direktoru', 'Direktor müavini', 'Tədris işləri üzrə direktor müavini'],
      schoolStaff: ['Müəllim', 'Sinif rəhbəri', 'Fənn müəllimi', 'Metodbirləşmə sədri', 'Psixoloq'],
      uniHead: ['Rektor', 'Prorektor', 'Dekan', 'Dekan müavini', 'Kafedra müdiri', 'Kollec direktoru'],
      uniStaff: ['Professor', 'Dosent', 'Baş müəllim', 'Müəllim', 'Assistent'],
      milHead: ['Akademiyanın rəisi', 'Hərbi liseyin rəisi', 'Məktəb rəisi', 'Fakültə rəisi', 'Kafedra rəisi', 'Bölük komandiri'],
      milStaff: ['Müəllim', 'Baş müəllim', 'Təlimatçı', 'Taqım komandiri', 'Kurs zabiti'],
      polHead: ['Polis Akademiyasının rəisi', 'Rəis müavini', 'Təlim mərkəzinin rəisi', 'Kafedra rəisi'],
      polStaff: ['Müəllim', 'Baş müəllim', 'Təlimatçı', 'Dosent'],
      genHead: ['Direktor', 'Direktor müavini', 'Təlim rəhbəri', 'Koordinator'],
      genStaff: ['Təlimçi', 'Müəllim', 'Təlimatçı'],
    ),
    TitleSystem(
      code: 'es',
      academic: ['Prof.', 'Profa.', 'Dr.', 'Dra.', 'Sr.', 'Sra.'],
      military: [
        'General de división', 'General de brigada', 'Coronel', 'Teniente coronel', 'Comandante', 'Capitán', 'Teniente',
        'Alférez', 'Suboficial mayor', 'Subteniente', 'Brigada', 'Sargento primero', 'Sargento',
      ],
      police: ['Comisario principal', 'Comisario', 'Inspector jefe', 'Inspector', 'Subinspector', 'Oficial', 'Agente'],
      schoolHead: ['Director/a', 'Subdirector/a', 'Jefe/a de estudios', 'Secretario/a'],
      schoolStaff: ['Profesor/a', 'Maestro/a', 'Tutor/a', 'Jefe/a de departamento', 'Orientador/a'],
      uniHead: ['Rector/a', 'Vicerrector/a', 'Decano/a', 'Vicedecano/a', 'Director/a de escuela', 'Director/a de departamento'],
      uniStaff: ['Catedrático/a', 'Profesor/a titular', 'Profesor/a contratado/a doctor/a', 'Profesor/a ayudante doctor/a', 'Profesor/a asociado/a', 'Ayudante'],
      milHead: ['Director/a de la Academia', 'Coronel director', 'Jefe/a de estudios', 'Jefe/a de batallón', 'Jefe/a de compañía'],
      milStaff: ['Profesor/a', 'Instructor/a', 'Jefe/a de sección', 'Profesor/a titular'],
      polHead: ['Director/a de la Escuela', 'Subdirector/a', 'Jefe/a de estudios', 'Coordinador/a'],
      polStaff: ['Profesor/a', 'Instructor/a', 'Formador/a', 'Tutor/a'],
      genHead: ['Director/a', 'Subdirector/a', 'Coordinador/a de formación', 'Responsable de formación'],
      genStaff: ['Formador/a', 'Profesor/a', 'Instructor/a', 'Monitor/a'],
    ),
    TitleSystem(
      code: 'it',
      academic: ['Prof.', 'Prof.ssa', 'Dott.', 'Dott.ssa', 'Ing.', 'Avv.'],
      military: [
        'Generale di corpo d’armata', 'Generale di divisione', 'Generale di brigata', 'Colonnello', 'Tenente colonnello',
        'Maggiore', 'Capitano', 'Tenente', 'Sottotenente', 'Primo luogotenente', 'Luogotenente', 'Primo maresciallo',
        'Maresciallo', 'Sergente maggiore', 'Sergente',
      ],
      police: [
        'Dirigente generale', 'Dirigente superiore', 'Primo dirigente', 'Vice questore', 'Vice questore aggiunto',
        'Commissario capo', 'Commissario', 'Ispettore superiore', 'Ispettore', 'Sovrintendente', 'Assistente', 'Agente',
      ],
      schoolHead: ['Dirigente scolastico', 'Vicepreside', 'Collaboratore del dirigente', 'Direttore dei servizi'],
      schoolStaff: ['Docente', 'Insegnante', 'Coordinatore di classe', 'Coordinatore di dipartimento', 'Docente di sostegno'],
      uniHead: ['Rettore', 'Prorettore', 'Preside di facoltà', 'Direttore di dipartimento', 'Presidente del corso di studio'],
      uniStaff: ['Professore ordinario', 'Professore associato', 'Ricercatore', 'Docente a contratto', 'Assegnista'],
      milHead: ['Comandante dell’Accademia', 'Comandante della Scuola', 'Direttore dei corsi', 'Comandante di battaglione', 'Comandante di compagnia'],
      milStaff: ['Docente', 'Istruttore', 'Comandante di plotone', 'Ufficiale istruttore'],
      polHead: ['Direttore della Scuola', 'Vice direttore', 'Direttore dei corsi', 'Coordinatore didattico'],
      polStaff: ['Docente', 'Istruttore', 'Formatore', 'Tutor'],
      genHead: ['Direttore', 'Vice direttore', 'Responsabile della formazione', 'Coordinatore'],
      genStaff: ['Formatore', 'Docente', 'Istruttore', 'Tutor'],
    ),
    TitleSystem(
      code: 'ar',
      academic: ['أ.د.', 'د.', 'أ.', 'م.'],
      military: ['فريق', 'لواء', 'عميد', 'عقيد', 'مقدم', 'رائد', 'نقيب', 'ملازم أول', 'ملازم', 'مساعد', 'رقيب أول', 'رقيب'],
      police: ['لواء شرطة', 'عميد شرطة', 'عقيد شرطة', 'مقدم شرطة', 'رائد شرطة', 'نقيب شرطة', 'ملازم أول شرطة', 'ملازم شرطة', 'أمين شرطة', 'رقيب شرطة'],
      schoolHead: ['مدير المدرسة', 'وكيل المدرسة', 'مساعد المدير', 'الموجه التربوي'],
      schoolStaff: ['معلم', 'معلمة', 'رائد الفصل', 'رئيس القسم', 'المرشد الطلابي'],
      uniHead: ['رئيس الجامعة', 'نائب رئيس الجامعة', 'عميد الكلية', 'وكيل الكلية', 'رئيس القسم', 'منسق البرنامج'],
      uniStaff: ['أستاذ', 'أستاذ مشارك', 'أستاذ مساعد', 'محاضر', 'مدرس', 'معيد'],
      milHead: ['مدير الكلية', 'قائد الكلية', 'آمر الكلية', 'مدير التعليم', 'قائد الكتيبة', 'قائد السرية'],
      milStaff: ['مدرس', 'مدرب', 'محاضر', 'قائد فصيلة', 'ضابط تدريب'],
      polHead: ['رئيس أكاديمية الشرطة', 'مدير أكاديمية الشرطة', 'مدير معهد الشرطة', 'مدير مركز التدريب', 'نائب المدير'],
      polStaff: ['مدرس', 'مدرب', 'محاضر', 'ضابط تدريب'],
      genHead: ['المدير', 'نائب المدير', 'مدير التدريب', 'المنسق'],
      genStaff: ['مدرب', 'معلم', 'محاضر', 'أخصائي تدريب'],
    ),
    TitleSystem(
      code: 'zh',
      academic: ['教授', '副教授', '博士', '研究员', '副研究员'],
      military: ['上将', '中将', '少将', '大校', '上校', '中校', '少校', '上尉', '中尉', '少尉', '一级军士长', '二级军士长', '上士', '中士', '下士'],
      police: ['总警监', '副总警监', '一级警监', '二级警监', '三级警监', '一级警督', '二级警督', '三级警督', '一级警司', '二级警司', '三级警司', '一级警员', '二级警员'],
      schoolHead: ['校长', '副校长', '教导主任', '年级主任', '教研组长'],
      schoolStaff: ['教师', '班主任', '学科教师', '高级教师', '一级教师', '心理教师'],
      uniHead: ['校长', '副校长', '党委书记', '院长', '副院长', '系主任', '教研室主任'],
      uniStaff: ['教授', '副教授', '讲师', '助教', '研究员'],
      milHead: ['院长', '政治委员', '副院长', '训练部部长', '教务处处长', '学员大队长', '学员队队长'],
      milStaff: ['教员', '教授', '副教授', '讲师', '教官', '区队长'],
      polHead: ['院长', '校长', '副院长', '培训中心主任', '教务处处长'],
      polStaff: ['教官', '讲师', '教授', '副教授', '教员'],
      genHead: ['主任', '副主任', '培训经理', '负责人'],
      genStaff: ['培训师', '讲师', '教师', '辅导员'],
    ),
    TitleSystem(
      code: 'ja',
      academic: ['教授', '准教授', '博士', '講師'],
      military: ['陸将', '陸将補', '1等陸佐', '2等陸佐', '3等陸佐', '1等陸尉', '2等陸尉', '3等陸尉', '准陸尉', '陸曹長', '1等陸曹', '2等陸曹', '3等陸曹'],
      police: ['警視監', '警視長', '警視正', '警視', '警部', '警部補', '巡査部長', '巡査長', '巡査'],
      schoolHead: ['校長', '副校長', '教頭', '主幹教諭', '学年主任'],
      schoolStaff: ['教諭', '担任', '指導教諭', '講師', '養護教諭', '非常勤講師'],
      uniHead: ['学長', '副学長', '学部長', '研究科長', '学科長', '専攻長'],
      uniStaff: ['教授', '准教授', '講師', '助教', '助手', '非常勤講師'],
      milHead: ['学校長', '副校長', '教育部長', '幹事', '学生隊長', '中隊長'],
      milStaff: ['教官', '教授', '准教授', '講師', '区隊長'],
      polHead: ['警察大学校長', '警察学校長', '副校長', '教務部長'],
      polStaff: ['教官', '講師', '教授', '助教', '術科教官'],
      genHead: ['所長', '副所長', '研修責任者', 'センター長'],
      genStaff: ['講師', '指導員', 'トレーナー', '教員'],
    ),
  ];
}

/// Grupların adı için seçenekler (uygulama dilinde).
List<String> groupLabelOptions(InstitutionType t) => [
      tr('Sınıf'),
      tr('Şube'),
      if (t == InstitutionType.military || t == InstitutionType.police) ...[
        tr('Bölük'),
        tr('Takım'),
        tr('Tabur'),
        tr('Devre'),
        tr('Dönem'),
      ],
      if (t == InstitutionType.university) ...[tr('Program'), tr('Bölüm')],
      tr('Grup'),
    ];
