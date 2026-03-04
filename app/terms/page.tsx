import { Shield, FileText, AlertTriangle } from "lucide-react";
import { Navbar } from "@/components/Navbar";
import Link from "next/link";

export default function TermsPage() {
    return (
        <main className="min-h-screen bg-gray-50 flex flex-col">
            <Navbar />

            <div className="flex-1 max-w-4xl mx-auto w-full px-4 py-12 pt-28">
                <div className="bg-white p-8 md:p-12 rounded-3xl shadow-sm border border-gray-100">

                    <div className="text-center mb-10 pb-10 border-b border-gray-100">
                        <div className="mx-auto w-16 h-16 bg-[var(--primary)] bg-opacity-10 rounded-full flex items-center justify-center text-[var(--primary)] mb-4">
                            <FileText size={32} />
                        </div>
                        <h1 className="text-3xl md:text-4xl font-extrabold text-gray-900 mb-4">
                            Kullanım Koşulları ve Son Kullanıcı Lisans Sözleşmesi (EULA)
                        </h1>
                        <p className="text-lg text-gray-500">
                            Son Güncelleme: {new Date().toLocaleDateString('tr-TR')}
                        </p>
                    </div>

                    <div className="prose prose-lg prose-gray max-w-none">

                        <div className="bg-red-50 border-l-4 border-red-500 p-6 rounded-r-xl mb-10 text-red-900">
                            <div className="flex items-start gap-3">
                                <AlertTriangle className="text-red-500 mt-1 flex-shrink-0" />
                                <div>
                                    <h3 className="text-lg font-bold text-red-700 m-0 mb-2">Önemli Bildirim: Sıfır Tolerans Politikası (UGC)</h3>
                                    <p className="m-0 text-sm md:text-base leading-relaxed">
                                        Teqlif platformu ("Uygulama"), Kullanıcı Tarafından Oluşturulan İçeriklerde (UGC) ve platform içi iletişimlerde
                                        <strong> sakıncalı içeriğe, nefret söylemine, zorbalığa ve tacize karşı SIFIR TOLERANS </strong>
                                        politikası uygulamaktadır. Bu kuralı ihlal eden kullanıcıların hesapları hiçbir uyarı yapılmaksızın
                                        <strong> 24 saat içerisinde kalıcı olarak kapatılacaktır.</strong>
                                    </p>
                                </div>
                            </div>
                        </div>

                        <h2 className="text-2xl font-bold text-gray-900 mt-8 mb-4 flex items-center gap-2">
                            <Shield className="text-[var(--primary)]" />
                            1. Kabul Edilemez Davranışlar ve İçerikler
                        </h2>
                        <p>Aşağıda belirtilen içeriklerin Uygulama içerisinde yayınlanması, mesajlaşma yoluyla iletilmesi veya herhangi bir şekilde paylaşılması kesinlikle yasaktır:</p>
                        <ul className="space-y-2">
                            <li>Irk, din, cinsiyet, cinsel yönelim veya diğer kişisel özelliklere yönelik nefret söylemleri ve aşağılayıcı ifadeler.</li>
                            <li>Diğer kullanıcıları tehdit eden, taciz eden veya zorbalık içeren davranışlar.</li>
                            <li>Müstehcen, pornografik veya cinsel olarak açık içerikler.</li>
                            <li>Yasadışı faaliyetleri teşvik eden veya destekleyen içerikler.</li>
                            <li>Spam, yanıltıcı bilgiler veya dolandırıcılık amaçlı paylaşımlar.</li>
                        </ul>

                        <h2 className="text-2xl font-bold text-gray-900 mt-8 mb-4">
                            2. Kullanıcı Raporlama ve Şikayet Mekanizması
                        </h2>
                        <p>
                            Teqlif, kullanıcılar tarafından oluşturulan içeriği denetleme hakkını saklı tutar ve kullanıcıların topluluk standartlarına uygun bir ortamda kalmasını sağlamak için
                            Kullanıcı Tarafından Oluşturulan İçerikleri (UGC) aktif olarak izler veya izlememesine bakılmaksızın kullanıcı geri bildirimlerini son derece ciddiye alır.
                        </p>
                        <p>
                            Platformdaki tüm ilan sayfalarında ve kullanıcı profillerinde "Şikayet Et" butonu bulunmaktadır. Şikayetleriniz destek ekibimiz tarafından
                            en geç 24 saat içerisinde incelenir. İnceleme sonucunda ihlal tespit edilen içerikler derhal kaldırılır ve ihlali gerçekleştiren
                            kullanıcı hesabı askıya alınır veya kalıcı olarak silinir.
                        </p>

                        <h2 className="text-2xl font-bold text-gray-900 mt-8 mb-4">
                            3. Engelleme (Block) Özelliği
                        </h2>
                        <p>
                            Anında müdahale hakkınız çerçevesinde, sizi rahatsız eden veya kuralları ihlal ettiğini düşündüğünüz kullanıcıları "Kullanıcıyı Engelle"
                            seçeneği ile anında engelleyebilirsiniz. Engellenen kullanıcılar sizinle bir daha iletişim kuramaz, ilanlarınızı göremez
                            ve aktif sohbetleriniz anında sonlandırılır.
                        </p>

                        <h2 className="text-2xl font-bold text-gray-900 mt-8 mb-4">
                            4. İletişim
                        </h2>
                        <p>
                            Kullanım koşulları hakkında sorularınız veya herhangi bir şikayetiniz için <Link href="/support" className="text-[var(--primary)] hover:underline font-medium">destek sayfamızdan</Link> veya doğrudan
                            <strong> destek@teqlif.com </strong> adresinden bizimle iletişime geçebilirsiniz.
                        </p>

                        <div className="mt-12 p-6 bg-gray-50 rounded-xl text-center text-sm text-gray-500 border border-gray-100">
                            Uygulamamızı kullanarak, yukarıdaki kuralları içeren Son Kullanıcı Lisans Sözleşmesi'ni (EULA) tamamen okuduğunuzu, anladığınızı ve koşulsuz olarak kabul ettiğinizi beyan etmiş olursunuz.
                        </div>

                    </div>
                </div>
            </div>
        </main>
    );
}
