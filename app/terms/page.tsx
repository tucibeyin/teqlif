import { Shield, FileText, AlertTriangle, AlertCircle, Users, BellOff } from "lucide-react";
import { Navbar } from "@/components/Navbar";
import Link from "next/link";

export default function TermsPage() {
    return (
        <main className="min-h-screen bg-gray-50/50 flex flex-col relative overflow-hidden">
            <Navbar />

            {/* Background Effects */}
            <div className="absolute top-0 left-0 w-full h-[500px] bg-gradient-to-b from-[var(--primary-50)] to-transparent opacity-60 pointer-events-none z-0" />
            <div className="absolute top-0 right-0 w-[600px] h-[600px] bg-[var(--primary)] opacity-[0.03] blur-[120px] rounded-full pointer-events-none z-0" />
            <div className="absolute top-40 left-[-200px] w-[500px] h-[500px] bg-purple-500 opacity-[0.02] blur-[100px] rounded-full pointer-events-none z-0" />

            <div className="flex-1 max-w-4xl mx-auto w-full px-4 py-16 pt-28 relative z-10">
                <div className="card shadow-[0_8px_30px_rgb(0,0,0,0.04)] sm:p-2 mb-8">
                    <div className="bg-white p-6 sm:p-10 md:p-14 rounded-[calc(var(--radius-xl)-8px)]">

                        {/* Header */}
                        <div className="text-center mb-12 pb-10 border-b border-[var(--border)] relative">
                            <div className="absolute bottom-0 left-1/2 -translate-x-1/2 w-24 h-1 bg-gradient-to-r from-transparent via-[var(--primary)] to-transparent opacity-30" />
                            <div className="mx-auto w-20 h-20 bg-[var(--primary-50)] rounded-3xl flex items-center justify-center text-[var(--primary)] mb-6 shadow-sm border border-[var(--primary-100)] transform rotate-3">
                                <FileText size={36} className="-rotate-3" />
                            </div>
                            <h1 className="text-3xl md:text-5xl font-extrabold text-gray-900 mb-5 tracking-tight">
                                Kullanım Koşulları <span className="text-gray-400 font-normal">ve</span> <br className="hidden sm:block" />
                                <span className="text-transparent bg-clip-text bg-gradient-to-r from-[var(--primary-dark)] to-[var(--primary)]">Lisans Sözleşmesi</span> (EULA)
                            </h1>
                            <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-gray-100 rounded-full text-sm text-gray-600 font-medium">
                                <span className="w-2 h-2 rounded-full bg-green-500"></span>
                                Son Güncelleme: {new Date().toLocaleDateString('tr-TR')}
                            </div>
                        </div>

                        <div className="prose prose-lg prose-gray max-w-none text-gray-600 space-y-10">

                            {/* Zero Tolerance Callout */}
                            <div className="relative overflow-hidden group">
                                <div className="absolute top-0 left-0 w-1.5 h-full bg-gradient-to-b from-red-500 to-red-600 rounded-l-2xl z-10" />
                                <div className="bg-[#FEF2F2] border border-[#FECACA] p-6 sm:p-8 rounded-2xl relative">
                                    <div className="absolute top-0 right-0 p-8 opacity-5 group-hover:opacity-10 transition-opacity">
                                        <AlertTriangle size={120} />
                                    </div>
                                    <div className="flex flex-col sm:flex-row items-start gap-4 sm:gap-6 relative z-10">
                                        <div className="w-14 h-14 bg-red-100 text-red-600 rounded-xl flex items-center justify-center shrink-0 shadow-sm">
                                            <AlertTriangle size={28} />
                                        </div>
                                        <div>
                                            <h3 className="text-xl font-bold text-red-800 m-0 mb-3 tracking-tight">Önemli Bildirim: Sıfır Tolerans Politikası (UGC)</h3>
                                            <p className="m-0 text-red-700 leading-relaxed">
                                                Teqlif platformu ("Uygulama"), Kullanıcı Tarafından Oluşturulan İçeriklerde (UGC) ve platform içi iletişimlerde
                                                <strong className="font-extrabold text-red-900"> sakıncalı içeriğe, nefret söylemine, zorbalığa ve tacize karşı SIFIR TOLERANS </strong>
                                                politikası uygulamaktadır. Bu kuralı ihlal eden kullanıcıların hesapları hiçbir uyarı yapılmaksızın
                                                <strong className="font-extrabold text-red-900 bg-red-200/50 px-1 rounded"> 24 saat içerisinde kalıcı olarak kapatılacaktır.</strong>
                                            </p>
                                        </div>
                                    </div>
                                </div>
                            </div>

                            {/* Section 1 */}
                            <section>
                                <h2 className="text-2xl font-bold text-gray-900 mb-5 flex items-center gap-3">
                                    <div className="w-10 h-10 bg-[var(--primary-50)] text-[var(--primary)] rounded-lg flex items-center justify-center">
                                        <Shield size={22} />
                                    </div>
                                    1. Kabul Edilemez Davranışlar ve İçerikler
                                </h2>
                                <div className="bg-gray-50 border border-gray-100 rounded-2xl p-6 sm:p-8 text-gray-600">
                                    <p className="mb-5 font-medium text-gray-700">Aşağıda belirtilen içeriklerin Uygulama içerisinde yayınlanması, mesajlaşma yoluyla iletilmesi veya herhangi bir şekilde paylaşılması kesinlikle yasaktır:</p>
                                    <ul className="space-y-3 m-0 pl-1 list-none">
                                        {[
                                            "Irk, din, cinsiyet, cinsel yönelim veya diğer kişisel özelliklere yönelik nefret söylemleri ve aşağılayıcı ifadeler.",
                                            "Diğer kullanıcıları tehdit eden, taciz eden veya zorbalık içeren davranışlar.",
                                            "Müstehcen, pornografik veya cinsel olarak açık içerikler.",
                                            "Yasadışı faaliyetleri teşvik eden veya destekleyen içerikler.",
                                            "Spam, yanıltıcı bilgiler veya dolandırıcılık amaçlı paylaşımlar."
                                        ].map((item, idx) => (
                                            <li key={idx} className="flex items-start gap-3">
                                                <span className="w-1.5 h-1.5 rounded-full bg-[var(--primary)] mt-2.5 shrink-0" />
                                                <span>{item}</span>
                                            </li>
                                        ))}
                                    </ul>
                                </div>
                            </section>

                            {/* Section 2 */}
                            <section>
                                <h2 className="text-2xl font-bold text-gray-900 mb-5 flex items-center gap-3">
                                    <div className="w-10 h-10 bg-[var(--primary-50)] text-[var(--primary)] rounded-lg flex items-center justify-center">
                                        <AlertCircle size={22} />
                                    </div>
                                    2. Raporlama ve Şikayet Mekanizması
                                </h2>
                                <div className="space-y-4">
                                    <p>
                                        Teqlif, kullanıcılar tarafından oluşturulan içeriği denetleme hakkını saklı tutar ve kullanıcıların topluluk standartlarına uygun bir ortamda kalmasını sağlamak için
                                        Kullanıcı Tarafından Oluşturulan İçerikleri (UGC) aktif olarak izler veya izlememesine bakılmaksızın kullanıcı geri bildirimlerini son derece ciddiye alır.
                                    </p>
                                    <div className="bg-[#F0FDF4] border border-[#BBF7D0] p-5 rounded-xl text-[#166534] flex gap-4 items-start">
                                        <Users className="shrink-0 text-[#16A34A] mt-1" size={24} />
                                        <p className="m-0 text-sm sm:text-base">
                                            Platformdaki tüm ilan sayfalarında ve kullanıcı profillerinde <strong className="font-bold">"Şikayet Et"</strong> butonu bulunmaktadır. Şikayetleriniz destek ekibimiz tarafından
                                            en geç 24 saat içerisinde incelenir. İnceleme sonucunda ihlal tespit edilen içerikler derhal kaldırılır ve ihlali gerçekleştiren
                                            kullanıcı hesabı askıya alınır veya kalıcı olarak silinir.
                                        </p>
                                    </div>
                                </div>
                            </section>

                            {/* Section 3 */}
                            <section>
                                <h2 className="text-2xl font-bold text-gray-900 mb-5 flex items-center gap-3">
                                    <div className="w-10 h-10 bg-[var(--primary-50)] text-[var(--primary)] rounded-lg flex items-center justify-center">
                                        <BellOff size={22} />
                                    </div>
                                    3. Engelleme (Block) Özelliği
                                </h2>
                                <p>
                                    Anında müdahale hakkınız çerçevesinde, sizi rahatsız eden veya kuralları ihlal ettiğini düşündüğünüz kullanıcıları <strong className="text-gray-900 bg-gray-100 px-2 py-0.5 rounded">"Kullanıcıyı Engelle"</strong>
                                    seçeneği ile anında engelleyebilirsiniz. Engellenen kullanıcılar sizinle bir daha iletişim kuramaz, ilanlarınızı göremez
                                    ve aktif sohbetleriniz anında sonlandırılır.
                                </p>
                            </section>

                            {/* Footer Note */}
                            <div className="mt-12 p-8 bg-gradient-to-br from-gray-50 to-gray-100 rounded-2xl text-center text-gray-600 border border-gray-200/60 shadow-inner">
                                <p className="mb-4">
                                    Kullanım koşulları hakkında sorularınız veya herhangi bir şikayetiniz için <Link href="/support" className="text-[var(--primary)] hover:text-[var(--primary-dark)] hover:underline font-semibold transition-colors">destek sayfamızdan</Link> veya doğrudan
                                    <a href="mailto:destek@teqlif.com" className="font-bold text-gray-800 hover:text-[var(--primary)] transition-colors ml-1">destek@teqlif.com</a> adresinden bizimle iletişime geçebilirsiniz.
                                </p>
                                <div className="w-12 h-px bg-gray-300 mx-auto my-5"></div>
                                <p className="text-sm text-gray-500 font-medium">
                                    Uygulamamızı kullanarak, yukarıdaki kuralları içeren Son Kullanıcı Lisans Sözleşmesi'ni (EULA) tamamen okuduğunuzu, anladığınızı ve koşulsuz olarak kabul ettiğinizi beyan etmiş olursunuz.
                                </p>
                            </div>

                        </div>
                    </div>
                </div>
            </div>
        </main>
    );
}
